#!/usr/bin/env bash
# sync/sync.sh [<nextbrain-ref>] — bring NextBrain into Alfaheem: fetch, merge, keep-list, identity, check.
# Stops with the merge UNCOMMITTED for review. Never pushes, never touches NextBrain (sync/README.md).
#   sync/sync.sh                       # merge nextbrain/production
#   sync/sync.sh f10567b1              # merge one NextBrain commit
set -euo pipefail
# Git Bash on Windows rewrites "<ref>:<path>" (a ref with a slash) as a path list; keep git arguments as written.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"
cd "$(git rev-parse --show-toplevel)"
REF="${1:-nextbrain/production}"

git remote get-url nextbrain >/dev/null 2>&1 || {
  echo "add the fetch-only remote first:"
  echo "  git remote add nextbrain D:/platform/nextbrain/nextbrain-front && git remote set-url --push nextbrain DISABLED"
  exit 1
}
[ "$(git remote get-url --push nextbrain)" = "DISABLED" ] || { echo "set the nextbrain push url to DISABLED first"; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo "commit or stash your changes first"; exit 1; }
case "$(git branch --show-current)" in production|main) echo "run this on a sync/ branch, not on $(git branch --show-current)"; exit 1;; esac

git fetch nextbrain production
PRE="$(git rev-parse HEAD)"
git -c merge.renameLimit=20000 merge --no-ff --no-commit "$REF" || true

# 1. Alfaheem's files win: the keep-list and the generated brand images, as they were before the merge.
grep -vhE '^\s*(#|$)' sync/keep_paths.txt sync/brand_assets.txt | while read -r f; do
  if git cat-file -e "$PRE:$f" 2>/dev/null; then git checkout "$PRE" -- "$f"; fi
done

# 2. Every other conflict: NextBrain's file. Alfaheem has no code of its own; everything Alfaheem changed outside
#    the keep-list was written by apply_identity.py, which runs again below.
git diff --name-only --diff-filter=U | while read -r f; do
  if git cat-file -e "$REF:$f" 2>/dev/null; then
    git checkout "$REF" -- "$f"
  else
    git rm -q --cached -- "$f" 2>/dev/null || true
    rm -f -- "$f"
  fi
done

# 3. Identity, generated images, the gate.
sync/post_merge.sh

echo
echo "Merge of $REF is staged but NOT committed. Review, run the gates (sync/README.md), then:"
echo "  git add -A && git commit"
