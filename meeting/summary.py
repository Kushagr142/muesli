import json
import os
import urllib.request

OPENAI_API_KEY_ENV = "OPENAI_API_KEY"
OPENAI_URL = "https://api.openai.com/v1/responses"

# Official lightweight GPT-5 model alias from OpenAI docs.
DEFAULT_MODEL = "gpt-5-mini"

SUMMARY_INSTRUCTIONS = """You are a meeting notes assistant. Given a raw meeting transcript, produce structured meeting notes with the following sections:

## Meeting Summary
A 2-3 sentence overview of what was discussed.

## Key Discussion Points
- Bullet points of main topics discussed

## Decisions Made
- Bullet points of any decisions reached

## Action Items
- [ ] Bullet points of tasks assigned or agreed upon, with owners if mentioned

## Notable Quotes
- Any important or notable statements (if applicable)

Keep it concise and professional. If a section has no content, write "None noted."
"""


def _load_api_key() -> str:
    api_key = os.environ.get(OPENAI_API_KEY_ENV, "")
    if api_key:
        return api_key

    config_path = os.path.expanduser("~/Library/Application Support/Muesli/config.json")
    if not os.path.exists(config_path):
        return ""

    with open(config_path) as f:
        cfg = json.load(f)
    return cfg.get("openai_api_key", "")


def _load_model_override() -> str | None:
    config_path = os.path.expanduser("~/Library/Application Support/Muesli/config.json")
    if not os.path.exists(config_path):
        return None

    with open(config_path) as f:
        cfg = json.load(f)
    return cfg.get("openai_model") or cfg.get("summary_model")


def _extract_output_text(result: dict) -> str:
    output_text = result.get("output_text")
    if output_text:
        return output_text.strip()

    for item in result.get("output", []):
        if item.get("type") != "message":
            continue
        for content in item.get("content", []):
            text = content.get("text")
            if text:
                return text.strip()
    return ""


def summarize_transcript(
    transcript: str,
    meeting_title: str = "",
    model: str | None = None,
) -> str:
    """Send transcript to OpenRouter for structured summarization.

    Returns formatted meeting notes as a string.
    Falls back to raw transcript if API is unavailable.
    """
    api_key = _load_api_key()

    if not api_key:
        print("[summary] No OpenAI API key found. Returning raw transcript.")
        print("[summary] Set OPENAI_API_KEY env var or add 'openai_api_key' to config.json")
        return f"# {meeting_title or 'Meeting Notes'}\n\n## Raw Transcript\n\n{transcript}"

    model = model or _load_model_override() or DEFAULT_MODEL
    payload = json.dumps({
        "model": model,
        "input": [
            {"role": "system", "content": SUMMARY_INSTRUCTIONS},
            {
                "role": "user",
                "content": (
                    f"Meeting title: {meeting_title or 'Untitled Meeting'}\n\n"
                    f"Raw transcript:\n{transcript}"
                ),
            },
        ],
        "reasoning": {"effort": "low"},
        "text": {"verbosity": "low"},
        "max_output_tokens": 1200,
    }).encode("utf-8")

    req = urllib.request.Request(
        OPENAI_URL,
        data=payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )

    try:
        print(f"[summary] Sending to OpenAI Responses API ({model})...")
        with urllib.request.urlopen(req, timeout=60) as resp:
            result = json.loads(resp.read())
            notes = _extract_output_text(result)
            if not notes:
                raise ValueError("OpenAI response did not contain summary text")
            print(f"[summary] Summary generated ({len(notes)} chars)")
            return f"# {meeting_title or 'Meeting Notes'}\n\n{notes}"
    except Exception as e:
        print(f"[summary] OpenAI error: {e}")
        return f"# {meeting_title or 'Meeting Notes'}\n\n## Raw Transcript\n\n{transcript}"
