#!/usr/bin/env python3
"""Helpers for detecting and deduplicating lab drift findings."""

import argparse
import hashlib
import re
from pathlib import Path


RESOURCE_PREVIEW = re.compile(
    r"^\s*resource\s+[A-Za-z_][A-Za-z0-9_]*\s+"
    r"'(?P<resource>[^'@\s]+)@(?P<version>\d{4}-\d{2}-\d{2}-preview)'",
    re.IGNORECASE | re.MULTILINE,
)
STRING_OR_COMMENT = re.compile(
    r"(?P<string>'''[\s\S]*?'''|'(?:\\.|[^'\\])*')"
    r"|(?P<comment>/\*[\s\S]*?\*/|//[^\n]*)"
)
LEGACY_AGE = re.compile(r"(Potentially stale apiVersion: \S+) \(~\d+ days old\)")
APPROVED_PREVIEWS = {
    ("microsoft.insights/diagnosticsettings", "2021-05-01-preview"),
}


def preview_findings(infra_dir: Path) -> list[str]:
    if not infra_dir.is_dir():
        raise FileNotFoundError(f"Bicep directory does not exist: {infra_dir}")

    paths = sorted(infra_dir.rglob("*.bicep"))
    if not paths:
        raise FileNotFoundError(f"No Bicep files found under: {infra_dir}")

    findings = set()
    for path in paths:
        text = path.read_text(encoding="utf-8")
        text = STRING_OR_COMMENT.sub(
            lambda match: match.group("string")
            or re.sub(r"[^\n]", " ", match.group("comment")),
            text,
        )
        for match in RESOURCE_PREVIEW.finditer(text):
            resource = match.group("resource")
            version = match.group("version")
            if (resource.lower(), version.lower()) in APPROVED_PREVIEWS:
                continue
            findings.add(
                f"Preview apiVersion in use: {resource}@{version} "
                "(review if a stable API version is available)."
            )
    return sorted(findings)


def fingerprint(lines: list[str]) -> str:
    normalized = {
        LEGACY_AGE.sub(r"\1", line.strip()) for line in lines if line.strip()
    }
    return hashlib.sha256("\n".join(sorted(normalized)).encode("utf-8")).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("preview-apis", "fingerprint"))
    parser.add_argument("path", type=Path)
    args = parser.parse_args()

    if args.command == "preview-apis":
        print("\n".join(preview_findings(args.path)))
    else:
        print(fingerprint(args.path.read_text(encoding="utf-8").splitlines()))


if __name__ == "__main__":
    main()
