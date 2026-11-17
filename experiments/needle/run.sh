#!/usr/bin/env bash
#
# Reproduce the Needle tool-design experiments recorded in
# docs/10-control-surface.md.
#
# These are EXPERIMENTS, not deliverables. The bash + coreutils rule governs
# tools/; this directory is where throwaway investigation lives, and it may use
# whatever it needs. Nothing here runs on the Pi or in the capture path.
#
# Needs network the first time, to fetch the engine and weights (~36 MB).
#
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
venv="${root}/build/needlevenv"
vendor="${root}/build/needle-vendor"

if [[ ! -x "${venv}/bin/python" ]]; then
    echo "==> creating venv (uv)"
    uv venv --python 3.13 "$venv"
    uv pip install --python "${venv}/bin/python" cactus-compute
fi

if [[ ! -f "${vendor}/needle3.cact" ]]; then
    mkdir -p "$vendor"
    echo "==> fetching engine + weights into ${vendor}"
    "${venv}/bin/cactus" fetch --out "$vendor"
    "${venv}/bin/cactus" download needle3 --out "$vendor"
fi

# Telemetry is ON by default in cactus-compute. This project is meant to work
# with no network at all, so it is switched off explicitly rather than relying
# on the absence of a route.
export CACTUS_TELEMETRY=0
export CACTUS_LIB_PATH="${vendor}/libcactus.so"
export NEEDLE_WEIGHTS="${vendor}/needle3.cact"

for probe in "${here}"/0*.py; do
    echo
    echo "=== ${probe##*/} ==="
    "${venv}/bin/python" "$probe"
done
