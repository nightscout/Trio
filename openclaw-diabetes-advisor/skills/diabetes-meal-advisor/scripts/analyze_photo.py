#!/usr/bin/env python3
"""
FatSecret Image Recognition for OpenClaw Diabetes Meal Advisor.

Takes an image path, sends it to FatSecret's image recognition API,
and returns structured JSON with detected foods and nutrition data.

Usage:
    python3 analyze_photo.py <image_path> [--eaten-foods eaten_foods.json]

Environment variables required:
    FATSECRET_CLIENT_ID
    FATSECRET_CLIENT_SECRET
"""

import base64
import json
import os
import sys
from io import BytesIO
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

TOKEN_URL = "https://oauth.fatsecret.com/connect/token"
RECOGNITION_URL = "https://platform.fatsecret.com/rest/image-recognition/v2"

MAX_IMAGE_DIMENSION = 512
MAX_BASE64_SIZE = 999_982
JPEG_QUALITY = 80


def get_credentials():
    client_id = os.environ.get("FATSECRET_CLIENT_ID", "")
    client_secret = os.environ.get("FATSECRET_CLIENT_SECRET", "")
    if not client_id or not client_secret:
        print(json.dumps({"error": "FATSECRET_CLIENT_ID and FATSECRET_CLIENT_SECRET must be set"}))
        sys.exit(1)
    return client_id, client_secret


def fetch_token(client_id, client_secret):
    credentials = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    body = "grant_type=client_credentials&scope=premier"

    req = Request(
        TOKEN_URL,
        data=body.encode(),
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Authorization": f"Basic {credentials}",
        },
        method="POST",
    )

    try:
        with urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
            return data["access_token"]
    except (HTTPError, KeyError) as e:
        print(json.dumps({"error": f"Failed to get FatSecret token: {e}"}))
        sys.exit(1)


def prepare_image(image_path):
    """Resize image to 512x512 and convert to base64 JPEG."""
    try:
        from PIL import Image
    except ImportError:
        # Fallback: read raw file and base64 encode without resizing
        with open(image_path, "rb") as f:
            raw = f.read()
        b64 = base64.b64encode(raw).decode()
        if len(b64) > MAX_BASE64_SIZE:
            print(json.dumps({"error": "Image too large. Install Pillow for auto-resize: pip install Pillow"}))
            sys.exit(1)
        return b64

    img = Image.open(image_path)

    # Convert to RGB if needed (handles RGBA, palette, etc.)
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")

    # Resize maintaining aspect ratio, fitting within 512x512
    img.thumbnail((MAX_IMAGE_DIMENSION, MAX_IMAGE_DIMENSION), Image.LANCZOS)

    buf = BytesIO()
    img.save(buf, format="JPEG", quality=JPEG_QUALITY)
    b64 = base64.b64encode(buf.getvalue()).decode()

    if len(b64) > MAX_BASE64_SIZE:
        # Try lower quality
        buf = BytesIO()
        img.save(buf, format="JPEG", quality=60)
        b64 = base64.b64encode(buf.getvalue()).decode()

    if len(b64) > MAX_BASE64_SIZE:
        print(json.dumps({"error": "Image still too large after compression"}))
        sys.exit(1)

    return b64


def call_recognition_api(token, base64_image, eaten_food_ids=None):
    body = {
        "image_b64": base64_image,
        "include_food_data": True,
        "region": "US",
        "language": "en",
    }

    if eaten_food_ids:
        body["eaten_foods"] = [{"food_id": fid} for fid in eaten_food_ids]

    payload = json.dumps(body).encode()

    req = Request(
        RECOGNITION_URL,
        data=payload,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urlopen(req, timeout=30) as resp:
            raw = json.loads(resp.read())
            # FatSecret may return errors in the response body with HTTP 200
            if "error" in raw:
                err = raw["error"]
                code = str(err.get("code", ""))
                msg = err.get("message", "")
                if code == "14":
                    return {
                        "error": "missing_scope",
                        "message": f"FatSecret API key lacks Image Recognition access. "
                        f"Enable it at https://platform.fatsecret.com — requires Premier plan. Detail: {msg}",
                    }
                return {"error": "api_error", "code": code, "message": msg}
            return raw
    except HTTPError as e:
        error_body = e.read().decode() if e.fp else ""
        try:
            error_data = json.loads(error_body)
            err = error_data.get("error", {})
            code = str(err.get("code", ""))
            if code == "211":
                return {"error": "nutrition_label", "message": "Detected a nutrition label instead of food. Photograph the actual food."}
            if code == "14":
                return {
                    "error": "missing_scope",
                    "message": "FatSecret API key lacks Image Recognition access. "
                    "Enable it at https://platform.fatsecret.com — requires Premier plan.",
                }
        except (json.JSONDecodeError, AttributeError):
            pass
        return {"error": "api_error", "status_code": e.code, "message": error_body}


def parse_serving(serving):
    """Parse a single serving option from FatSecret response."""
    return {
        "id": serving.get("serving_id", ""),
        "description": serving.get("serving_description", ""),
        "metric_amount": float(serving.get("metric_serving_amount", 0) or 0),
        "metric_unit": serving.get("metric_serving_unit", "g"),
        "number_of_units": serving.get("number_of_units", "1"),
        "is_default": serving.get("is_default") == "1",
        "carbs": float(serving.get("carbohydrate", 0) or 0),
        "fat": float(serving.get("fat", 0) or 0),
        "protein": float(serving.get("protein", 0) or 0),
        "calories": float(serving.get("calories", 0) or 0),
        "sugar": float(serving.get("sugar", 0) or 0),
    }


def parse_response(response):
    """Parse FatSecret recognition response into structured food list."""
    if "error" in response:
        return response

    food_responses = response.get("food_response", [])
    if not food_responses:
        return {"error": "no_food_detected", "message": "No food detected in the image. Try photographing from above with better lighting."}

    foods = []
    for item in food_responses:
        eaten = item.get("eaten")
        if not eaten:
            continue

        nutrition = eaten.get("total_nutritional_content", {}) or {}
        food_data = item.get("food") or {}

        # Parse alternative servings (handle both single object and array)
        servings_container = food_data.get("servings", {}) or {}
        raw_servings = servings_container.get("serving", [])
        if isinstance(raw_servings, dict):
            raw_servings = [raw_servings]
        alternative_servings = [parse_serving(s) for s in raw_servings[:5]]

        suggested = item.get("suggested_serving") or {}

        food = {
            "food_id": item.get("food_id"),
            "name": item.get("food_entry_name", "Unknown food"),
            "food_type": food_data.get("food_type", "Generic"),
            "name_singular": eaten.get("food_name_singular", ""),
            "name_plural": eaten.get("food_name_plural", ""),
            "serving_description": suggested.get("serving_description", ""),
            "portion_grams": eaten.get("total_metric_amount", 0) or 0,
            "per_unit_grams": eaten.get("per_unit_metric_amount", 0) or 0,
            "carbs": float(nutrition.get("carbohydrate", 0) or 0),
            "fat": float(nutrition.get("fat", 0) or 0),
            "protein": float(nutrition.get("protein", 0) or 0),
            "calories": float(nutrition.get("calories", 0) or 0),
            "sugar": float(nutrition.get("sugar", 0) or 0),
            "fiber": float(nutrition.get("fiber", 0) or 0),
            "alternative_servings": alternative_servings,
        }
        foods.append(food)

    if not foods:
        return {"error": "no_food_detected", "message": "No food detected in the image."}

    # Compute totals
    totals = {
        "carbs": round(sum(f["carbs"] for f in foods), 1),
        "fat": round(sum(f["fat"] for f in foods), 1),
        "protein": round(sum(f["protein"] for f in foods), 1),
        "calories": round(sum(f["calories"] for f in foods), 1),
        "sugar": round(sum(f["sugar"] for f in foods), 1),
        "fiber": round(sum(f["fiber"] for f in foods), 1),
    }
    totals["net_carbs"] = round(totals["carbs"] - totals["fiber"], 1)

    return {
        "foods": foods,
        "totals": totals,
        "count": len(foods),
    }


def load_eaten_foods(path):
    """Load previously eaten food IDs from JSON file."""
    if not path or not Path(path).exists():
        return []
    try:
        with open(path) as f:
            data = json.load(f)
        return [str(item.get("food_id", item)) for item in data if item]
    except (json.JSONDecodeError, TypeError):
        return []


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Usage: analyze_photo.py <image_path> [--eaten-foods <path>]"}))
        sys.exit(1)

    image_path = sys.argv[1]

    # Parse optional --eaten-foods argument
    eaten_foods_path = None
    if "--eaten-foods" in sys.argv:
        idx = sys.argv.index("--eaten-foods")
        if idx + 1 < len(sys.argv):
            eaten_foods_path = sys.argv[idx + 1]

    if not Path(image_path).exists():
        print(json.dumps({"error": f"Image not found: {image_path}"}))
        sys.exit(1)

    client_id, client_secret = get_credentials()
    token = fetch_token(client_id, client_secret)
    base64_image = prepare_image(image_path)
    eaten_food_ids = load_eaten_foods(eaten_foods_path)

    raw_response = call_recognition_api(token, base64_image, eaten_food_ids)
    result = parse_response(raw_response)

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
