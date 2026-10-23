#!/usr/bin/env bash
# Fast test run: real git (no xcrun shim), one bats process per test file in parallel.
# Usage: test/fast.sh [files...]   Env: JOBS (default: cpu count), RAMDISK=1 (tmp on a RAM volume)
set -u
cd "$(dirname "$0")/.."
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
AI_TEST_GIT_DIR="$(dirname "$(xcrun -f git 2>/dev/null || command -v git)")"; export AI_TEST_GIT_DIR
OUT="$(mktemp -d)"
dev=""
cleanup() {
  [ -z "$dev" ] || hdiutil detach "$dev" -quiet -force 2>/dev/null
  rm -rf "$OUT"
}
trap cleanup EXIT
if [ "${RAMDISK:-0}" = 1 ] && command -v hdiutil >/dev/null; then
  dev="$(hdiutil attach -nomount ram://1048576 | awk '{print $1}')"
  diskutil erasevolume HFS+ aiu-test "$dev" >/dev/null && export TMPDIR=/Volumes/aiu-test/
fi
if [ $# -gt 0 ]; then files=("$@"); else files=(test/*.bats); fi
printf '%s\n' "${files[@]}" | xargs -P "$JOBS" -I{} sh -c 'bats {} > "$0/$(basename {}).out" 2>&1; echo $? > "$0/$(basename {}).rc"' "$OUT"
fail=0
for f in "${files[@]}"; do
  b="$(basename "$f")"; rc="$(cat "$OUT/$b.rc" 2>/dev/null || echo 1)"
  ok="$(grep -c '^ok' "$OUT/$b.out")"; nok="$(grep -c '^not ok' "$OUT/$b.out")"
  printf '%-22s ok=%-3s not_ok=%-3s rc=%s\n' "$b" "$ok" "$nok" "$rc"
  if [ "$rc" != 0 ]; then fail=1; grep '^not ok' "$OUT/$b.out"; fi
done
exit "$fail"
