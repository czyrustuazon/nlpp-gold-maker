#!/usr/bin/env bash
# One-time setup for the Azahar smoke boot (.github/workflows/smoke.yml).
# Re-run after pushing changes to azahar-3ds-accurate.
#
#   sudo bash scripts/setup-smoke-runner.sh            # /opt/nlpp, fork main
#   sudo bash scripts/setup-smoke-runner.sh /opt/nlpp <ref>
#
# Builds github.com/czyrustuazon/azahar-3ds-accurate (Azahar + OpenLinkFile
# clone + NLPP_EMU_* hardware-crash replays) inside Azahar's own CI image, so
# the host needs Docker, not Qt dev packages. Output: $ROOT/azahar/azahar.AppImage.
# The build is slow on a 2-core laptop (expect 1-3 hours); -j2 keeps clang
# under the RAM of a small box.

set -euo pipefail
ROOT="${1:-/opt/nlpp}"
REF="${2:-main}"
FORK=https://github.com/czyrustuazon/azahar-3ds-accurate.git
IMAGE=opensauce04/azahar-build-environment:latest
SRC="$ROOT/src/azahar-3ds-accurate"
JOBS="${NLPP_AZAHAR_JOBS:-2}"

apt-get update
# xvfb + xauth: headless X for xvfb-run. Mesa: llvmpipe software OpenGL.
apt-get install -y docker.io git xvfb xauth libgl1-mesa-dri libegl1 libglx-mesa0 fonts-dejavu-core

mkdir -p "$ROOT/src" "$ROOT/azahar" "$ROOT/smoke"
if [ ! -d "$SRC/.git" ]; then
  git clone "$FORK" "$SRC"
fi
git -C "$SRC" fetch origin
git -C "$SRC" checkout --force "origin/$REF" 2>/dev/null || git -C "$SRC" checkout --force "$REF"
git -C "$SRC" clean -fdx -e build
git -C "$SRC" submodule update --init --recursive

# Same flags as Azahar's .ci/linux.sh appimage target.
docker run --rm -v "$SRC:/src" -w /src -e HOME=/tmp "$IMAGE" bash -euxc "
  cmake -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang \
    -DCMAKE_LINKER=/etc/bin/ld.lld \
    -DENABLE_ROOM_STANDALONE=OFF
  ninja -C build -j $JOBS
  ninja -C build bundle
"

APPIMAGE=$(find "$SRC/build/bundle" -maxdepth 1 -name 'azahar*.AppImage' | head -n 1)
if [ -z "$APPIMAGE" ]; then
  echo "no AppImage under $SRC/build/bundle" >&2
  exit 1
fi
install -m 0755 "$APPIMAGE" "$ROOT/azahar/azahar.AppImage"
git -C "$SRC" rev-parse HEAD > "$ROOT/azahar/FORK_COMMIT"
echo "ok $ROOT/azahar/azahar.AppImage (fork $(cut -c1-9 "$ROOT/azahar/FORK_COMMIT"))"
echo
echo "Next (see README.md, Azahar smoke boot):"
echo "  1. Copy a decrypted New Love Plus+ .3ds/.cci to $ROOT/vanilla/rom.3ds"
echo "  2. Copy an Azahar user folder's sdmc/ and nand/ (a title save) to $ROOT/smoke/seed_user/"
echo "  3. Add to the runner .env: NLPP_SMOKE_AZAHAR, NLPP_ROM, NLPP_SMOKE_SEED_USER"
