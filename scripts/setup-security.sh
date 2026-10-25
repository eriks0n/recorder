#!/bin/bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
managed="$(git rev-parse --absolute-git-dir)/recorder-security"
existing="$(git config --get core.hooksPath || true)"
if [[ -n "$existing" && "$existing" != ".githooks" && "$existing" != "$managed/hooks" ]]; then
    echo "Existing hooksPath preserved: integrate the secret checks with your existing hooks." >&2
    exit 1
fi
if [[ -z "$existing" ]]; then
    for hook in pre-commit pre-push; do
        if [[ -f "$(git rev-parse --git-path "hooks/$hook")" ]]; then
            echo "Existing $hook preserved: integrate the secret checks with it first." >&2
            exit 1
        fi
    done
fi
python3 scripts/install-secret-scanner.py
# Keep hooks, checker and scanner outside the checkout so branch switches or
# cleaning .build cannot silently disable protection.
mkdir -p "$managed/hooks" "$managed/scripts" "$managed/.build/security-tools"
cp scripts/check-secrets.py "$managed/scripts/check-secrets.py"
cp .build/security-tools/gitleaks "$managed/.build/security-tools/gitleaks"
cp .githooks/pre-commit "$managed/hooks/pre-commit"
cp .githooks/pre-push "$managed/hooks/pre-push"
chmod 700 "$managed/hooks/pre-commit" "$managed/hooks/pre-push" "$managed/.build/security-tools/gitleaks"
git config --local core.hooksPath "$managed/hooks"
echo "Secret protection enabled for commits and pushes, including after branch switches."
