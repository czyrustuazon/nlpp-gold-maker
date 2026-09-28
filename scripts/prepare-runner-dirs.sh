#!/usr/bin/env bash
# Create runner folders on Ubuntu. Does NOT register the GitHub runner.
#   sudo bash scripts/prepare-runner-dirs.sh
#   sudo bash scripts/prepare-runner-dirs.sh /home/you/nlpp

set -euo pipefail
ROOT="${1:-/opt/nlpp}"

mkdir -p \
  "$ROOT/vanilla/romfs/SystemData/TextResource" \
  "$ROOT/vanilla/exefs" \
  "$ROOT/actions-runner" \
  "$ROOT/cache/img_pack" \
  "$ROOT/repo"

echo "ok $ROOT/vanilla/romfs/..."
echo "ok $ROOT/vanilla/exefs"
echo "ok $ROOT/actions-runner"
echo "ok $ROOT/cache/img_pack"
echo "ok $ROOT/repo  (optional; CI checks out EngPatcher each job)"
echo
echo "Next:"
echo "  1. Copy vanilla img.bin + TextResource TRBs under $ROOT/vanilla/romfs/"
echo "     and exefs code.bin under $ROOT/vanilla/exefs/"
echo "  2. Export NLPP_VANILLA_* / NLPP_PACK_CACHE (see README.md / .env.example)"
echo "  3. Install GitHub Actions runner (Linux x64) into $ROOT/actions-runner"
echo "     — register it to this repo"
echo "  4. Set EngPatcher secret NLPP_GOLD_DISPATCH_TOKEN + var NLPP_GOLD_REPO=OWNER/THIS_REPO,"
echo "     then push EngPatcher main"
