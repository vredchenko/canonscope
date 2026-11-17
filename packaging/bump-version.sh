#!/usr/bin/env bash
#
# bump-version.sh X.Y.Z -- set the version everywhere it is written.
#
# Then commit, tag and push; the tag is what makes a release:
#   git commit -am "chore: release vX.Y.Z"
#   git tag -a vX.Y.Z -m vX.Y.Z
#   git push origin main vX.Y.Z
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."
new="${1:?usage: bump-version.sh X.Y.Z}"
new="${new#v}"
[[ "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "'$new' is not X.Y.Z" >&2; exit 1; }
printf '%s\n' "$new" > VERSION
sed -i "s/\(\"version\"[[:space:]]*:[[:space:]]*\"\)[^\"]*\"/\1${new}\"/" \
    .claude-plugin/plugin.json .claude-plugin/marketplace.json
packaging/check-version.sh
