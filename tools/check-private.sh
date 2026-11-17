#!/usr/bin/env bash
#
# check-private.sh -- refuse to let private identifiers into this public tree.
#
# This repository is public. There is no scrubbing step between a contributor's
# working files and GitHub, so the guard sits on the source.
#
# Two pattern sets:
#   generic   shipped here: tailnet names, RFC1918 and CGNAT addresses, MACs,
#             absolute home paths, private keys, GitHub tokens.
#   personal  NOT shipped, optional: ~/.config/canonscope/private-patterns,
#             one extended regex per line -- your own hostnames, domains and
#             usernames. That list is by construction the thing it protects,
#             so it lives outside the repo. Override the path with
#             CANONSCOPE_PRIVATE_PATTERNS.
#
# Usage:
#   tools/check-private.sh               scan every tracked file
#   tools/check-private.sh FILE...       scan these (what the pre-commit hook does)
#   tools/check-private.sh --install-hook
#
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/common.sh"

PRIVATE_LIST="${CANONSCOPE_PRIVATE_PATTERNS:-$HOME/.config/canonscope/private-patterns}"

GENERIC=(
    'tail[0-9a-f]{5,}\.ts\.net'
    '\b192\.168\.[0-9]{1,3}\.[0-9]{1,3}\b'
    '\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b'
    '\b100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}\b'
    '\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b'
    # absolute home paths -- left-bounded so URLs like .org/home/uv/ do not match
    '(^|[[:space:]"'"'"'=:(])/home/[a-z][a-z0-9_-]*/'
    'BEGIN [A-Z ]*PRIVATE KEY'
    'gh[pousr]_[A-Za-z0-9]{20,}'
)

if [[ "${1:-}" == "--install-hook" ]]; then
    [[ -d "${CANONSCOPE_ROOT}/.git" ]] || die "not a git repository"
    HOOK="${CANONSCOPE_ROOT}/.git/hooks/pre-commit"
    cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
# Installed by tools/check-private.sh --install-hook
cd "$(git rev-parse --show-toplevel)"
mapfile -t files < <(git diff --cached --name-only --diff-filter=ACMR)
(( ${#files[@]} )) || exit 0
exec tools/check-private.sh "${files[@]}"
EOF
    chmod +x "$HOOK"
    ok "installed $HOOK"
    exit 0
fi

if (( $# )); then
    FILES=("$@")
elif git -C "$CANONSCOPE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    mapfile -t FILES < <(git -C "$CANONSCOPE_ROOT" ls-files)
else
    mapfile -t FILES < <(cd "$CANONSCOPE_ROOT" && find . -type f -not -path './.git/*' -not -path './assets/*' -not -path './build/*' -not -path './captures/*' | sed 's|^\./||')
fi

PATTERNS=("${GENERIC[@]}")
if [[ -r "$PRIVATE_LIST" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        PATTERNS+=("$line")
    done < "$PRIVATE_LIST"
else
    info "no personal pattern list at $PRIVATE_LIST -- generic patterns only"
fi

RE="$(IFS='|'; echo "${PATTERNS[*]}")"
HITS=0
cd "$CANONSCOPE_ROOT"
for f in "${FILES[@]}"; do
    [[ -f "$f" ]] || continue
    # Binary files are not prose; skip them rather than match inside a zip.
    grep -qI . "$f" 2>/dev/null || continue
    OUT="$(grep -nE "$RE" "$f" 2>/dev/null || true)"
    [[ -z "$OUT" ]] && continue
    HITS=$((HITS+1))
    printf '%s%s%s\n' "$C_RED" "$f" "$C_RESET"
    printf '%s\n' "$OUT" | sed -n '1,8{s/^/    /;p}'
done

if (( HITS )); then
    die "$HITS file(s) contain private identifiers -- fix the source, do not widen the exclusions"
fi
ok "${#FILES[@]} files clean"
