#!/usr/bin/env python3
"""Compose a build's TestFlight "What to Test" notes.

Shared by both distribution workflows so the two cannot drift. Reads the
triggering commit's message on stdin and writes the finished notes to the
path given as the only argument.

Git trailers are dropped: a tester reading "What to Test" has no use for
Co-Authored-By or Claude-Session lines, and they crowd a field that is
already capped.

Which keys count is an explicit allowlist rather than git's own
`interpret-trailers`, which treats any "Word: text" line as a trailer —
this repository's commit bodies routinely end paragraphs with prose like
"macOS: ..." or "Verified: ...", and those must survive into the notes.
"""

import os
import sys

# App Store Connect rejects a whatsNew longer than this.
CHARACTER_LIMIT = 4000

# Compared case-insensitively. Add a key here rather than loosening the
# match, so prose is never mistaken for metadata.
TRAILER_KEYS = frozenset(
    {
        "acked-by",
        "cc",
        "claude-session",
        "co-authored-by",
        "helped-by",
        "reported-by",
        "reviewed-by",
        "signed-off-by",
        "suggested-by",
        "tested-by",
    }
)


def is_trailer(line: str) -> bool:
    key, separator, _ = line.partition(":")
    return bool(separator) and key.strip().lower() in TRAILER_KEYS


def strip_trailers(message: str) -> str:
    """Remove the commit's trailer block, if it has one."""
    paragraphs = message.strip().split("\n\n")
    # Trailers are the final paragraph by definition, and only qualify
    # when every line in it is one.
    while len(paragraphs) > 1:
        lines = [line for line in paragraphs[-1].splitlines() if line.strip()]
        if lines and all(is_trailer(line) for line in lines):
            paragraphs.pop()
        else:
            break
    return "\n\n".join(paragraphs).strip()


def main() -> None:
    destination = sys.argv[1]
    body = strip_trailers(sys.stdin.read())

    footer = "\n".join(
        [
            "Commit {} on {}".format(
                os.environ.get("GITHUB_SHA", "")[:7],
                os.environ.get("GITHUB_REF_NAME", ""),
            ),
            "Pipeline run #{}".format(os.environ.get("GITHUB_RUN_NUMBER", "")),
            "{}/{}/actions/runs/{}".format(
                os.environ.get("GITHUB_SERVER_URL", ""),
                os.environ.get("GITHUB_REPOSITORY", ""),
                os.environ.get("GITHUB_RUN_ID", ""),
            ),
        ]
    )
    notes = f"{body}\n\n{footer}\n" if body else f"{footer}\n"

    # Truncate on a character boundary: cutting bytes could split a
    # multi-byte character and leave invalid UTF-8 in the upload.
    with open(destination, "w", encoding="utf-8") as handle:
        handle.write(notes[:CHARACTER_LIMIT])


if __name__ == "__main__":
    main()
