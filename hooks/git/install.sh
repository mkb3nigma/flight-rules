#!/usr/bin/env bash
# One-time setup: wire the repo's committed git hooks into git.
# Copy the hooks into the project (e.g. .ai/hooks/), then run from the repo root:
#   bash .ai/hooks/install.sh

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
HOOKS_DIR="$REPO_ROOT/.ai/hooks"   # adjust if the project keeps hooks elsewhere

# commit-msg carries the note gate. Without it, pre-merge-commit blocks PR-only
# branches but nothing enforces the pre-merge-check note — a half-built gate that
# still looks installed. Fail loudly rather than degrade silently.
for required in pre-merge-commit post-merge commit-msg; do
    if [ ! -f "$HOOKS_DIR/$required" ]; then
        echo "❌ $HOOKS_DIR/$required is missing — copy it in before installing."
        [ "$required" = "commit-msg" ] && echo "   Without it the note gate never runs and merges go unchecked."
        exit 1
    fi
    chmod +x "$HOOKS_DIR/$required"
done

# Point git at the committed hooks directory
git config core.hooksPath "$HOOKS_DIR"

# Disable fast-forward merges so pre-merge-commit always fires on merge
git config merge.ff false

echo "✅ git hooks installed"
echo "   core.hooksPath = $(git config core.hooksPath)"
echo ""
echo "   Active hooks:"
for f in "$HOOKS_DIR"/*; do
    [[ "$(basename "$f")" == *.* ]] && continue  # skip .sh/.md — git only runs bare hook names
    echo "     $(basename "$f")"
done
