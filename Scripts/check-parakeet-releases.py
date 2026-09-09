#!/usr/bin/env python3
"""Check whether a newer parakeet speech model exists than the one we ship.

Two things can go stale, and each is checked against what the app actually
pins rather than against a state file, so there is nothing to keep in sync:

  1. The GGUF repo we download from has moved past the revision pinned in
     ModelStore.swift -- a requantisation, or a rebuild against a newer base.
  2. NVIDIA has published a parakeet model newer than the base model our GGUF
     was quantised from, which is how a whole new generation shows up.

Findings go to stdout and, under Actions, to $GITHUB_OUTPUT as `has_findings`,
`digest` (stable per set of findings, so the workflow only notifies once),
`title`, `message` and `link`.
"""

import argparse
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

HF_API = "https://huggingface.co/api"
MODEL_STORE = os.path.join(os.path.dirname(__file__), "..", "TypeMeIt", "ModelStore.swift")

# The one line that names both the repo and the exact revision we ship.
PINNED = re.compile(
    r"https://huggingface\.co/(?P<repo>[^/\s]+/[^/\s]+)/resolve/(?P<sha>[0-9a-f]{40})/"
)


def get_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "typemeit-parakeet-watch"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def pinned_model():
    with open(MODEL_STORE, encoding="utf-8") as handle:
        match = PINNED.search(handle.read())
    if match is None:
        sys.exit(f"no pinned huggingface revision found in {MODEL_STORE}")
    return match.group("repo"), match.group("sha")


def speaks_english(tags):
    """Skip the per-language forks. A bare two-letter tag is a language code on
    the Hub, so a model that names languages but not English is not for us."""
    languages = {tag for tag in tags if len(tag) == 2 and tag.islower()}
    return not languages or "en" in languages


def check():
    repo, pinned_sha = pinned_model()
    info = get_json(f"{HF_API}/models/{urllib.parse.quote(repo)}")
    findings = []

    head = info.get("sha")
    if head and head != pinned_sha:
        findings.append(
            {
                "id": f"revision:{repo}:{head}",
                "headline": f"{repo} has a new revision",
                "detail": (
                    f"Pinned `{pinned_sha[:12]}`, now `{head[:12]}` "
                    f"(changed {info.get('lastModified', 'unknown')}).\n"
                    "ModelStore.swift needs the new revision in both URLs, plus a fresh "
                    "`sha256` and `expectedBytes` for the file."
                ),
                "link": f"https://huggingface.co/{repo}/commits/main",
            }
        )

    # `base_model` is what the GGUF was quantised from; anything NVIDIA published
    # after it is a candidate to move to.
    base = (info.get("cardData") or {}).get("base_model")
    if isinstance(base, list):
        base = base[0] if base else None
    if base:
        base_created = get_json(f"{HF_API}/models/{urllib.parse.quote(base)}").get("createdAt", "")
        listing = get_json(
            f"{HF_API}/models?author=nvidia&search=parakeet&sort=createdAt&direction=-1&limit=100"
        )
        for model in listing:
            model_id = model.get("id")
            created = model.get("createdAt", "")
            if model_id == base or not created or created <= base_created:
                continue
            if not speaks_english(model.get("tags") or []):
                continue
            findings.append(
                {
                    "id": f"newer-base:{model_id}",
                    "headline": f"{model_id} is newer than the base model we use",
                    "detail": (
                        f"Published {created}; our base model `{base}` dates from {base_created}."
                    ),
                    "link": f"https://huggingface.co/{model_id}",
                }
            )

    return findings


def emit(findings):
    title = (
        findings[0]["headline"]
        if len(findings) == 1
        else f"{len(findings)} parakeet model updates"
    )
    message = "\n\n".join(
        f"**{f['headline']}**\n\n{f['detail']}\n\n{f['link']}" for f in findings
    )
    digest = hashlib.sha256(
        "\n".join(sorted(f["id"] for f in findings)).encode()
    ).hexdigest()[:16]

    print(title)
    print()
    print(message)

    output = os.environ.get("GITHUB_OUTPUT")
    if not output:
        return
    with open(output, "a", encoding="utf-8") as handle:
        handle.write("has_findings=true\n")
        handle.write(f"digest={digest}\n")
        handle.write(f"title={title}\n")
        handle.write(f"link={findings[0]['link']}\n")
        handle.write(f"message<<PARAKEET_EOF\n{message}\nPARAKEET_EOF\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force",
        action="store_true",
        help="report a synthetic finding so the notification path can be tested",
    )
    args = parser.parse_args()

    try:
        findings = check()
    except (urllib.error.URLError, json.JSONDecodeError) as error:
        sys.exit(f"huggingface lookup failed: {error}")

    if args.force and not findings:
        repo, sha = pinned_model()
        findings = [
            {
                "id": f"test:{repo}:{sha}",
                "headline": "parakeet watch test",
                "detail": f"Nothing has changed. {repo} is still pinned at `{sha[:12]}`.",
                "link": f"https://huggingface.co/{repo}",
            }
        ]

    if not findings:
        print("up to date")
        output = os.environ.get("GITHUB_OUTPUT")
        if output:
            with open(output, "a", encoding="utf-8") as handle:
                handle.write("has_findings=false\n")
        return

    emit(findings)


if __name__ == "__main__":
    main()
