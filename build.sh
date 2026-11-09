#!/usr/bin/env bash
# Builds and tests everything on Linux or macOS; the counterpart of build.ps1.
#   ./build.sh
#
# Looks for the libraries next to each other, as on Windows:
#   <dev>/shared_libraries/TPlugInFramework   this repository
#   <dev>/lazarus_libraries/{fresnel,ohsRibbon,ohsmultigrid,ohsganttcomponents}
# Set LIBS_DIR to the folder that holds them, or FRESNEL_DIR, RIBBON_DIR, MULTIGRID_DIR and
# GANTT_DIR one by one. Set LAZBUILD to use another lazbuild, SKIA_LIB to the Skia library
# (libsk4d.so or libsk4d.dylib) when Fresnel has none for this platform.
#
# The packages are registered in a Lazarus configuration of its own under out/lazcfg-<target>,
# so the configuration of the IDE is not touched.
# Exit codes: 0 ok, 1 tests failed, 2 tools or libraries missing, 4 build failed.
# The last line is BUILD OK, TESTS PASSED only when everything succeeded.

set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

LAZBUILD="${LAZBUILD:-lazbuild}"
LIBS_DIR="${LIBS_DIR:-$(cd "$ROOT/../.." 2>/dev/null && pwd)/lazarus_libraries}"
FRESNEL_DIR="${FRESNEL_DIR:-$LIBS_DIR/fresnel}"
RIBBON_DIR="${RIBBON_DIR:-$LIBS_DIR/ohsRibbon}"
MULTIGRID_DIR="${MULTIGRID_DIR:-$LIBS_DIR/ohsmultigrid}"
GANTT_DIR="${GANTT_DIR:-$LIBS_DIR/ohsganttcomponents}"

case "$(uname -s)" in
  Linux)  OS=linux;  LIBEXT=so ;;
  Darwin) OS=darwin; LIBEXT=dylib ;;
  *) echo "Use build.ps1 on Windows: $(uname -s)"; exit 2 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) CPU=x86_64 ;;
  arm64|aarch64) CPU=aarch64 ;;
  *) echo "Unknown CPU: $(uname -m)"; exit 2 ;;
esac
TARGET="$CPU-$OS"
OUT="$ROOT/demo/fresnel/out/$TARGET"
LAZCONFIG="$ROOT/out/lazcfg-$TARGET"
LOG="$ROOT/out/build-$TARGET.log"

if [ -z "${SKIA_LIB:-}" ]; then
  case "$TARGET" in
    x86_64-linux) SKIA_LIB="$FRESNEL_DIR/bin/Binary/Shared/Linux64/libsk4d.so" ;;
    *) SKIA_LIB="" ;;
  esac
fi

command -v "$LAZBUILD" >/dev/null || { echo "lazbuild not found: $LAZBUILD"; exit 2; }
for f in "$FRESNEL_DIR/src/fresnel.lpk" "$RIBBON_DIR/src/ohsribbon.lpk" \
         "$MULTIGRID_DIR/src/fresnel/pkg_multigrid_fresnel.lpk" "$GANTT_DIR/ganttcomponents.lpk"; do
  [ -f "$f" ] || { echo "Not found: $f (set LIBS_DIR or the *_DIR variables)"; exit 2; }
done
if [ -z "$SKIA_LIB" ] || [ ! -f "$SKIA_LIB" ]; then
  echo "No Skia library for $TARGET in Fresnel; set SKIA_LIB to libsk4d.$LIBEXT"
  exit 2
fi

mkdir -p "$ROOT/out" "$OUT"
: >"$LOG"

build() {
  if ! "$LAZBUILD" --pcp="$LAZCONFIG" "$@" >>"$LOG" 2>&1; then
    echo "Build failed: ${*: -1}, see $LOG"
    tail -n 20 "$LOG"
    exit 4
  fi
}

echo "=== $TARGET"
for package in \
  "$FRESNEL_DIR/src/base/fresnelbase.lpk" "$FRESNEL_DIR/src/fresnel.lpk" \
  "$RIBBON_DIR/src/ohsribbon.lpk" "$MULTIGRID_DIR/src/fresnel/pkg_multigrid_fresnel.lpk" \
  "$GANTT_DIR/ganttcomponents.lpk" \
  packages/lazarus/ohspluginframework.lpk packages/lazarus/ohspluginframework_fresnel.lpk \
  packages/lazarus/ohspluginframework_ribbon.lpk packages/lazarus/ohspluginframework_multigrid.lpk \
  packages/lazarus/ohspluginframework_gantt.lpk; do
  build --add-package-link "$package"
done
for project in \
  packages/lazarus/ohspluginframework.lpk packages/lazarus/ohspluginframework_fresnel.lpk \
  packages/lazarus/ohspluginframework_ribbon.lpk packages/lazarus/ohspluginframework_multigrid.lpk \
  packages/lazarus/ohspluginframework_gantt.lpk \
  demo/fresnel/plugins/hello/hello.lpi demo/fresnel/plugins/floatcheck/floatcheck.lpi \
  demo/fresnel/host/ohsplugindemo.lpi test/testframework.lpi; do
  build "$project"
done

cp "$SKIA_LIB" "$OUT/"

export LD_LIBRARY_PATH="$OUT${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export DYLD_LIBRARY_PATH="$OUT${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"

if ! test/testframework "$OUT/plugins"; then
  echo "Framework tests failed"
  exit 1
fi
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || [ "$OS" = darwin ]; then
  if ! "$OUT/ohsplugindemo" --selftest; then
    echo "Demo self test failed"
    exit 1
  fi
else
  echo "No display: the demo self test is skipped"
fi

echo "BUILD OK, TESTS PASSED. Run $OUT/ohsplugindemo"
