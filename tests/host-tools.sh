#!/usr/bin/env bash
# Verify extraction cleanup without a Docker daemon or firmware compilation.
set -euo pipefail
project=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
mkdir -p "$work/bin" "$work/fixture/host" "$work/tree/scripts"
printf 'host tools fixture\n' > "$work/fixture/host/tool"
printf '#!/bin/sh\nprintf "refresh\\n" >> "$TOOLS_LOG"\n' > "$work/tree/scripts/ext-tools.sh"
cat > "$work/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TOOLS_LOG"
case "$1" in
  manifest) exit 0 ;;
  create) printf 'fixture-container\n' ;;
  cp)
    [[ ${TOOLS_COPY_FAIL:-0} != 1 ]] || exit 7
    tar -cf - -C "$TOOLS_FIXTURE" host
    ;;
  rm|image) exit 0 ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$work/bin/docker" "$work/tree/scripts/ext-tools.sh"
export PATH="$work/bin:$PATH" TOOLS_LOG=$work/log TOOLS_FIXTURE=$work/fixture
export OPENWRTROOT=$work/tree BRANCH=main
for disposable in 0 1; do
  : > "$TOOLS_LOG"
  REXWRT_DISPOSABLE_DOCKER=$disposable GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=github-hosted \
    bash "$project/tools/external-host-tools.sh" > "$work/output"
  cmp "$work/fixture/host/tool" "$work/tree/staging_dir/host/tool"
  cmp "$work/fixture/host/tool" "$work/tree/build_dir/host/tool"
  grep -qx 'rm fixture-container' "$TOOLS_LOG" || fail 'container retained'
  grep -qx refresh "$TOOLS_LOG" || fail 'tools not refreshed'
  if [[ $disposable == 1 ]]; then
    grep -qx 'image rm ghcr.io/openwrt/tools:latest' "$TOOLS_LOG" || fail 'temporary image retained'
  elif grep -q '^image rm ' "$TOOLS_LOG"; then
    fail 'image removed outside dedicated store'
  fi
done
: > "$TOOLS_LOG"
if TOOLS_COPY_FAIL=1 REXWRT_DISPOSABLE_DOCKER=1 GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=github-hosted \
  bash "$project/tools/external-host-tools.sh" > "$work/error" 2>&1; then
  fail 'extraction failure ignored'
fi
grep -qx 'rm fixture-container' "$TOOLS_LOG" || fail 'failed extraction retained container'
grep -qx 'image rm ghcr.io/openwrt/tools:latest' "$TOOLS_LOG" || fail 'failed extraction retained image'
if grep -qx refresh "$TOOLS_LOG"; then fail 'incomplete extraction refreshed'; fi
printf 'PASS: host tools extraction preserves failures and cleans dedicated runner storage\n'
