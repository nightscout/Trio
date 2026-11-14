#!/usr/bin/env python3
"""Build the on-device Trio Docs index used by the in-app docs assistant.

The settings search bar can answer free-text questions with the on-device
Apple Intelligence model (iOS 26+). The model never browses the web: it only
sees passages from this index, which the app searches locally (BM25) and hands
to the model as context. Everything therefore stays on the phone.

This script downloads the public MkDocs search index of https://triodocs.org
and turns it into a compact list of text chunks:

    Trio/Resources/json/docs/trio-docs-index.json

The `json` folder is bundled as a folder reference, so the file ships with the
app without any Xcode project changes.

Usage:
    python3 scripts/build-docs-index.py                 # download and rebuild
    python3 scripts/build-docs-index.py --input FILE    # use a saved search_index.json
    python3 scripts/build-docs-index.py --output FILE   # write somewhere else

Re-run it whenever the documentation changes notably and commit the result.
Standard library only.
"""

import argparse
import datetime as _dt
import html
import json
import re
import sys
import urllib.request
from pathlib import Path

SOURCE_URL = "https://triodocs.org/search/search_index.json"
BASE_URL = "https://triodocs.org/"
DEFAULT_OUTPUT = Path(__file__).resolve().parent.parent / "Trio/Resources/json/docs/trio-docs-index.json"

# Chunks longer than this are split at sentence boundaries ...
MAX_CHUNK_CHARS = 1400
# ... into pieces of roughly this size.
TARGET_CHUNK_CHARS = 900
# Chunks shorter than this carry no usable information (e.g. "See below.").
MIN_CHUNK_CHARS = 40
# Relevance multipliers by page path prefix. Migration pages are mostly comparison tables that
# mention every setting once, so they outrank the real explanations unless damped a little.
PAGE_WEIGHTS = {"configuration/migration/": 0.8}
# The docs mark pages that haven't been updated for the current Trio version with a pencil.
OUTDATED_MARK = "\u270f"

_TAG_RE = re.compile(r"<[^>]+>")
_LIST_ITEM_RE = re.compile(r"<li[^>]*>", re.IGNORECASE)
_BLOCK_RE = re.compile(r"</(p|li|pre|h[1-6]|tr|div)>|<br\s*/?>", re.IGNORECASE)
_WS_RE = re.compile(r"\s+")
_SENTENCE_RE = re.compile(r"(?<=[.!?:])\s+")
# Header injected into every page by the docs' PDF/print plugin.
_PRINT_HEADER_RE = re.compile(r"TrioDocs\s+Version:.*?https://triodocs\.org\s*", re.DOTALL)
# Fallback text of embedded videos; meaningless without the video.
_VIDEO_FALLBACK_RE = re.compile(r"Your browser doesn.t support the HTML5 video tag\.?\s*")


def clean_text(raw: str) -> str:
    """Turn the HTML-ish search index text into plain text with list bullets kept."""
    text = _LIST_ITEM_RE.sub(" • ", raw)
    text = _BLOCK_RE.sub(" ", text)
    text = _TAG_RE.sub(" ", text)
    text = html.unescape(text)
    text = _PRINT_HEADER_RE.sub(" ", text)
    text = _WS_RE.sub(" ", text)
    text = _VIDEO_FALLBACK_RE.sub(" ", text)
    return _WS_RE.sub(" ", text).strip()


def split_chunk(text: str) -> list[str]:
    """Split a long passage into sentence-aligned pieces of about TARGET_CHUNK_CHARS."""
    if len(text) <= MAX_CHUNK_CHARS:
        return [text]

    pieces: list[str] = []
    current = ""
    for sentence in _SENTENCE_RE.split(text):
        # A single overlong sentence (e.g. a list rendered inline) is cut at whitespace.
        while len(sentence) > MAX_CHUNK_CHARS:
            cut = sentence.rfind(" ", 0, TARGET_CHUNK_CHARS)
            cut = cut if cut > 0 else TARGET_CHUNK_CHARS
            head, sentence = sentence[:cut].strip(), sentence[cut:].strip()
            if current:
                pieces.append(current)
                current = ""
            pieces.append(head)

        if current and len(current) + 1 + len(sentence) > TARGET_CHUNK_CHARS:
            pieces.append(current)
            current = sentence
        else:
            current = f"{current} {sentence}".strip()

    if current:
        pieces.append(current)
    return pieces


def build_chunks(index: dict) -> list[dict]:
    docs = index["docs"]

    # The entry without an anchor is the page itself; it only carries the print header,
    # but its title is the page title we want for breadcrumbs.
    page_titles: dict[str, str] = {}
    for entry in docs:
        location = entry["location"]
        if "#" not in location:
            page_titles[location] = clean_text(entry.get("title", "")) or location

    chunks: list[dict] = []
    seen: set[tuple[str, str]] = set()
    for entry in docs:
        location = entry["location"]
        if "#" not in location:
            continue
        page_path = location.split("#", 1)[0]
        page = page_titles.get(page_path) or clean_text(entry.get("title", "")) or page_path
        section = clean_text(entry.get("title", "")) or page
        text = clean_text(entry.get("text", ""))
        if len(text) < MIN_CHUNK_CHARS:
            continue
        weight = next((w for prefix, w in PAGE_WEIGHTS.items() if page_path.startswith(prefix)), None)
        outdated = OUTDATED_MARK in page or OUTDATED_MARK in section
        for piece in split_chunk(text):
            key = (location, piece)
            if key in seen:
                continue
            seen.add(key)
            chunk = {
                "id": len(chunks),
                "location": location,
                "page": page,
                "section": section,
                "text": piece,
            }
            if weight is not None:
                chunk["weight"] = weight
            if outdated:
                chunk["outdated"] = True
            chunks.append(chunk)
    return chunks


def write_index(chunks: list[dict], output: Path, generated: str) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    # One chunk per line keeps diffs reviewable when the index is regenerated.
    with output.open("w", encoding="utf-8") as fh:
        fh.write("{\n")
        fh.write(f'"version": 1,\n')
        fh.write(f'"source": {json.dumps(SOURCE_URL)},\n')
        fh.write(f'"baseURL": {json.dumps(BASE_URL)},\n')
        fh.write(f'"generated": {json.dumps(generated)},\n')
        fh.write('"chunks": [\n')
        for i, chunk in enumerate(chunks):
            fh.write(json.dumps(chunk, ensure_ascii=False, separators=(",", ":")))
            fh.write(",\n" if i < len(chunks) - 1 else "\n")
        fh.write("]\n}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--input", type=Path, help="use a previously downloaded search_index.json instead of downloading")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help=f"where to write the index (default: {DEFAULT_OUTPUT})")
    args = parser.parse_args()

    if args.input:
        raw = args.input.read_text(encoding="utf-8")
    else:
        print(f"Downloading {SOURCE_URL} …", file=sys.stderr)
        with urllib.request.urlopen(SOURCE_URL, timeout=60) as response:
            raw = response.read().decode("utf-8")

    index = json.loads(raw)
    chunks = build_chunks(index)
    if len(chunks) < 100:
        print(f"error: only {len(chunks)} chunks produced, the index format may have changed", file=sys.stderr)
        return 1

    generated = _dt.date.today().isoformat()
    write_index(chunks, args.output, generated)

    pages = {c["location"].split("#", 1)[0] for c in chunks}
    chars = sum(len(c["text"]) for c in chunks)
    longest = max(len(c["text"]) for c in chunks)
    print(f"wrote {args.output}", file=sys.stderr)
    print(f"  {len(chunks)} chunks from {len(pages)} pages, {chars:,} characters, longest chunk {longest} characters", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
