# On-device docs assistant (settings search)

Typing a free-text question into the settings search bar offers **Ask Trio Docs**. The answer is
generated on the phone by the Apple Intelligence model (Foundation Models framework, iOS 26+) from a
copy of https://triodocs.org that ships inside the app. Nothing leaves the device, and the feature is
hidden on devices that can never run it (iOS < 26, hardware without Apple Intelligence).

## Pieces

| File | Role |
| --- | --- |
| `scripts/build-docs-index.py` | Downloads the MkDocs search index of triodocs.org and writes the bundled passage index. |
| `Trio/Resources/json/docs/trio-docs-index.json` | ~830 passages (page, section, text, optional `weight`/`outdated`). Bundled through the `json` folder reference, so no project changes are needed when it is regenerated. |
| `Sources/Services/DocsAssistant/DocsIndex.swift` | In-memory BM25 search over the passages, with a light English stemmer, German/everyday-word synonyms on the query side and a boost for passages whose section or page title the question covers. |
| `Sources/Services/DocsAssistant/DocsAssistant.swift` | The pipeline (see below), availability mapping, prompt assembly (`DocsAssistantPrompt`, testable without the model) and error mapping. |
| `Sources/Modules/Settings/View/DocsAssistantView.swift` | The sheet: question, streamed answer, the sections it was based on (deep links into triodocs.org), disclaimer, follow-up field. |
| `TrioTests/DocsIndexTests.swift` | Tokenizer, ranking, context selection, prompt and bundled-index tests. |

## Pipeline per question

1. **Rewrite.** A short structured-output call turns the question into an English translation plus the
   setting/feature names it mentions. This is what makes non-English questions find the English docs.
2. **Search.** BM25 over question + translation + names, top 10.
3. **Select.** Up to 6 passages within ~5,500 characters; the first 3 are always taken, further ones only
   if they score at least half of the best hit. The on-device model has a context window of about 4,000
   tokens shared by instructions, passages, question and answer, so this budget matters.
4. **Answer.** A fresh `LanguageModelSession` with fixed instructions streams the answer. The prompt
   names the language to answer in (detected with `NLLanguageRecognizer`, falling back to the device
   language for very short questions) and flags passages from pages the docs mark as not yet updated (✏️).
   If the context window overflows, the question is retried once with half the passages.

Every question is independent; there is no chat history.

## Safety framing

The instructions tell the model to answer only from the passages, to say so when they don't cover the
question, to use plain language, to keep the docs' safety warnings, and never to recommend specific
values for anyone's insulin settings but to point to the care team instead. The sheet shows a permanent
disclaimer that answers can be wrong and are not medical advice. Apple's own guardrails may decline a
question; that surfaces as a friendly "declined" message with a link to the docs.

## Regenerating the index

```sh
python3 scripts/build-docs-index.py
```

Re-run when the documentation changes notably and commit the regenerated JSON. The script needs only
the Python standard library. `--input FILE` reuses a saved `search_index.json`, `--output FILE` writes
elsewhere.

## Trying it without a phone

The assistant and index files have no UIKit dependency, so a macOS 26 Mac with Apple Intelligence can
run them from a small command-line harness:

```sh
swiftc -target arm64-apple-macos26.0 -sdk "$(xcrun --sdk macosx --show-sdk-path)" -swift-version 5 \
  Trio/Sources/Services/DocsAssistant/DocsIndex.swift \
  Trio/Sources/Services/DocsAssistant/DocsAssistant.swift \
  main.swift -o harness
```

where `main.swift` loads `DocsIndex(contentsOf:)` and iterates `DocsAssistant(index:).ask(question)`.
This is the quickest way to tune retrieval or the instructions.
