#!/usr/bin/env python3
"""Check whether a newer parakeet speech model exists than the one we ship.

Two things can go stale, and each is checked against what the app actually
pins rather than against a state file, so there is nothing to keep in sync:

  1. The GGUF we download has been rebuilt -- a requantisation, or a rebuild
     against a newer base. Checked by hashing, not by revision: the repo's head
     moves for README edits too, and those are not our problem.
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

# What ModelStore.swift pins: the repo, and the file plus digest the app will
# accept. The digest is the real baseline -- it is what the app checks after
# downloading, so it is what "has the model changed" has to mean here.
PINNED_REPO = re.compile(
    r"https://huggingface\.co/(?P<repo>[^/\s]+/[^/\s]+)/resolve/(?P<revision>[0-9a-f]{40})/"
)
PINNED_FILE = re.compile(r'let fileName = "(?P<name>[^"]+)"')
PINNED_SHA = re.compile(r'let sha256 = "(?P<sha256>[0-9a-f]{64})"')


def get_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "typemeit-parakeet-watch"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def pinned_model():
    with open(MODEL_STORE, encoding="utf-8") as handle:
        source = handle.read()
    pins = {}
    for pattern in (PINNED_REPO, PINNED_FILE, PINNED_SHA):
        match = pattern.search(source)
        if match is None:
            sys.exit(f"{MODEL_STORE} no longer pins what this script reads")
        pins.update(match.groupdict())
    return pins


def speaks_english(tags):
    """Skip the per-language forks. A bare two-letter tag is a language code on
    the Hub, so a model that names languages but not English is not for us."""
    languages = {tag for tag in tags if len(tag) == 2 and tag.islower()}
    return not languages or "en" in languages


def check():
    pins = pinned_model()
    repo, name, pinned_sha = pins["repo"], pins["name"], pins["sha256"]
    info = get_json(f"{HF_API}/models/{urllib.parse.quote(repo)}?blobs=true")
    findings = []

    # `lfs.sha256` is the digest of the file itself, so this compares the bytes
    # the app would download against the bytes it is willing to accept.
    sibling = next((s for s in info.get("siblings", []) if s.get("rfilename") == name), None)
    if sibling is None:
        findings.append(
            {
                "id": f"missing:{repo}:{name}",
                "headline": f"{name} is gone from {repo}",
                "detail": "The app downloads this file by name. Nothing will install until "
                "ModelStore.swift points somewhere that has it.",
                "link": f"https://huggingface.co/{repo}/tree/main",
            }
        )
    else:
        current = (sibling.get("lfs") or {}).get("sha256")
        if current and current != pinned_sha:
            findings.append(
                {
                    "id": f"rebuilt:{repo}:{current}",
                    "headline": f"{name} has been rebuilt",
                    "detail": (
                        f"Pinned `{pinned_sha[:16]}`, now `{current[:16]}` "
                        f"({sibling.get('size', '?')} bytes, changed "
                        f"{info.get('lastModified', 'unknown')}).\n"
                        "ModelStore.swift needs the new revision in the URL, plus this "
                        "`sha256` and `expectedBytes`."
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
        pins = pinned_model()
        findings = [
            {
                "id": f"test:{pins['repo']}:{pins['sha256']}",
                "headline": "parakeet watch test",
                "detail": f"Nothing has changed. {pins['name']} still hashes to "
                f"`{pins['sha256'][:16]}`.",
                "link": f"https://huggingface.co/{pins['repo']}",
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
