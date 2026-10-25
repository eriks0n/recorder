#!/usr/bin/env python3
"""Fail closed on prohibited filenames or detected secrets; never print file contents."""
import argparse
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys

SCRIPT_ROOT = Path(__file__).resolve().parent.parent

def git(*args):
    return subprocess.check_output(["git", *args])

def prohibited(path):
    parts = PurePosixPath(path).parts
    for component in parts:
        name = component.lower()
        if name in {"taskinbox", ".direnv", ".aws", ".ssh", ".terraform"}:
            return True
        if name.startswith((".env", ".secret", "credentials", "secrets", "id_rsa", "id_ed25519")):
            return True
        if re.search(r"\.env(?:\.|$)", name):
            return True
        if name in {".netrc", ".npmrc", ".pypirc", ".git-credentials", "inbox.json", "processing-queue.json", "profiles.json", "transcript.json", "transcript.md", "summary.json", "summary.md", "meeting.json", "current-result.json", "current-summary.json"}:
            return True
        if name.endswith((".pem", ".key", ".p12", ".pfx", ".jks", ".keystore", ".mobileprovision", ".tfvars", ".tfvars.json", ".csv", ".caf", ".m4a", ".mp3", ".wav", ".flac", ".aac", ".ogg", ".opus", ".aiff", ".aif")):
            return True
        if name.startswith(("profiles.json.",)) or ".tfstate" in name:
            return True
    return False

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["staged", "history"])
    parser.add_argument("--pre-push", action="store_true")
    args = parser.parse_args()
    pushed = []
    if args.pre_push:
        for line in sys.stdin:
            fields = line.split()
            if len(fields) != 4 or not re.fullmatch(r"(?:[a-fA-F0-9]{40}|[a-fA-F0-9]{64})", fields[1]):
                print("BLOCKED: invalid push reference input.", file=sys.stderr)
                return 2
            if set(fields[1]) != {"0"}:
                pushed.append(fields[1])
        if not pushed:
            return 0  # Deleting remote refs does not upload secrets.

    if args.mode == "staged":
        raw = git("diff", "--cached", "--name-only", "--diff-filter=ACMRT", "-z")
        names = raw.decode("utf-8", "surrogateescape").split("\0")
    else:
        # Inspect every tree, including filenames deleted in later commits.
        names = []
        for commit in git("rev-list", "--all", *pushed).decode().splitlines():
            names.extend(git("ls-tree", "-r", "--name-only", "-z", commit).decode("utf-8", "surrogateescape").split("\0"))
    blocked = sorted({path for path in names if path and prohibited(path)})
    if blocked:
        print("BLOCKED: private/environment file paths must never be versioned:", file=sys.stderr)
        for path in blocked:
            print("  " + ascii(path), file=sys.stderr)
        return 1
    scanner = SCRIPT_ROOT / ".build/security-tools/gitleaks"
    if not scanner.is_file():
        found = shutil.which("gitleaks")
        if not found:
            print("BLOCKED: Gitleaks missing. Run ./scripts/setup-security.sh first.", file=sys.stderr)
            return 2
        scanner = Path(found)
    env = os.environ.copy()
    env.pop("GITLEAKS_CONFIG", None)
    env.pop("GITLEAKS_CONFIG_TOML", None)
    command = [str(scanner), "git", "--redact=100", "--no-banner", "--no-color", "--ignore-gitleaks-allow", "--gitleaks-ignore-path=/dev/null"]
    # No repository-specific allowlists or baseline exclusions.
    import tempfile
    with tempfile.TemporaryDirectory(prefix="recorder-secret-policy-") as temporary:
        config = Path(temporary) / "gitleaks.toml"
        config.write_text("[extend]\nuseDefault = true\n")
        command += ["--config", str(config)]
        if args.mode == "staged":
            command += ["--pre-commit", "--staged"]
        else:
            command += ["--log-opts=" + " ".join(["--all", "--full-history", *pushed])]
        result = subprocess.run(command, env=env, capture_output=True)
        diagnostics = result.stdout + result.stderr
        scanner_error = any(marker in diagnostics for marker in [b" ERR ", b"ERR ", b" FTL ", b"fatal:", b"error="])
        if result.returncode != 0 or scanner_error:
            print("BLOCKED: Gitleaks detected a secret or could not complete the scan. Inspect locally with --redact=100; do not bypass this check.", file=sys.stderr)
            return 1
        print("Secret check passed.")
        return 0

if __name__ == "__main__":
    raise SystemExit(main())
