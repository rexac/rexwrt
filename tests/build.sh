#!/usr/bin/env bash
# Check host tools, official Go imports and workflow retention without network or compilation.
set -euo pipefail
project=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

test_host_tools() (
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
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
)

test_golang() (
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/source/lang/golang/golang"
cat > "$work/bin/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GO_GIT_LOG"
if [[ "$1" == clone ]]; then
  [[ "$*" == *'--branch master https://github.com/openwrt/packages '* ]]
  mkdir -p "${!#}"
  cp -R "$GO_SOURCE_FIXTURE/." "${!#}/"
elif [[ "$3" == sparse-checkout ]]; then
  [[ "$*" == *'sparse-checkout set lang/golang' ]]
elif [[ "$3" == rev-parse ]]; then
  printf '1111111111111111111111111111111111111111\n'
else
  exit 1
fi
MOCK
chmod +x "$work/bin/git"
export PATH="$work/bin:$PATH" GO_SOURCE_FIXTURE=$work/source GO_GIT_LOG=$work/git.log
manifest() { (cd "$1" && find . -type f -exec shasum -a 256 {} + | LC_ALL=C sort); }
for version in 1.27 1.43; do
  incoming=$work/source/lang/golang
  rm -rf "$incoming"
  mkdir -p "$incoming/golang" "$incoming/golang-bootstrap" "$incoming/golang$version"
  printf 'PKG_NAME:=golang\n' > "$incoming/golang/Makefile"
  printf 'PKG_NAME:=golang-bootstrap\n' > "$incoming/golang-bootstrap/Makefile"
  printf 'PKG_NAME:=golang%s\nGO_VERSION_MAJOR_MINOR:=%s\n' "$version" "$version" > "$incoming/golang$version/Makefile"
  for file in golang-package.mk golang-values.mk golang-version.mk; do printf 'official helper\n' > "$incoming/$file"; done
  tree=$work/tree-$version
  mkdir -p "$tree/feeds/packages/lang/golang/golang1.26" "$tree/feeds/packages/net/tailscale" \
    "$tree/package/feeds/packages" "$tree/scripts" "$tree/tmp"
  printf 'PKG_NAME:=golang1.26\n' > "$tree/feeds/packages/lang/golang/golang1.26/Makefile"
  printf 'PKG_BUILD_DEPENDS:=golang%s/host other/host\n' "$version" > "$tree/feeds/packages/net/tailscale/Makefile"
  printf 'stale metadata\n' > "$tree/tmp/.packageinfo"
  printf 'CONFIG_PACKAGE_tailscale=y\n' > "$tree/.config"
  cat > "$tree/scripts/feeds" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GO_FEEDS_LOG"
printf 'refreshed config\n' > "$OPENWRTROOT/.config"
if [[ "$1" == install ]]; then
  [[ "$2" == -p && "$3" == packages ]]
  shift 3
  for name in "$@"; do
    ln -sfn "$OPENWRTROOT/feeds/packages/lang/golang/$name" "$OPENWRTROOT/package/feeds/packages/$name"
  done
fi
MOCK
  chmod +x "$tree/scripts/feeds"
  export OPENWRTROOT=$tree GO_FEEDS_LOG=$work/feeds-$version.log
  bash -c 'source "$1"; update_golang' _ "$project/scripts/customize/patches.sh" > "$work/log"
  cmp "$incoming/golang$version/Makefile" "$tree/feeds/packages/lang/golang/golang$version/Makefile"
  grep -qx "PKG_BUILD_DEPENDS:=golang$version/host other/host" "$tree/feeds/packages/net/tailscale/Makefile" || fail 'package dependencies rewritten'
  [[ -f "$tree/package/feeds/packages/golang$version/Makefile" ]] || fail 'new host recipe not installed'
  [[ -f "$tree/package/feeds/packages/golang1.26/Makefile" ]] || fail 'older compiler removed'
  [[ ! -e "$tree/tmp/.packageinfo" ]] || fail 'stale package metadata retained'
  grep -qx 'CONFIG_PACKAGE_tailscale=y' "$tree/.config" || fail 'feed refresh changed configuration seeds'
  [[ $(head -1 "$GO_FEEDS_LOG") == 'update -i packages' ]] || fail 'feed index not refreshed first'
  jq -e '.repository == "https://github.com/openwrt/packages" and .branch == "master" and .retained_feed_compilers == ["golang1.26"]' \
    "$tree/.rexwrt/golang-source.json" >/dev/null || fail 'source metadata incorrect'
  [[ ! -e "$tree/files/etc/rexwrt/golang-source.json" ]] || fail 'Go build metadata copied into firmware'

  rm "$incoming/golang-package.mk"
  manifest "$tree" > "$work/before"
  if bash -c 'source "$1"; update_golang' _ "$project/scripts/customize/patches.sh" > "$work/error" 2>&1; then fail 'incomplete upstream accepted'; fi
  manifest "$tree" > "$work/after"
  cmp "$work/before" "$work/after" || fail 'invalid upstream modified checkout'
done
printf 'PASS: official Go master imports follow versions, retain stable compilers and refresh host links\n'
)

test_workflow_cleanup() (
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
jq -n '
  def run($id; $workflow; $number; $status; $date):
    {id:$id, workflow_id:$workflow, run_number:$number, status:$status, updated_at:$date};
  "2000-01-01T00:00:00Z" as $old | "2999-01-01T00:00:00Z" as $recent |
  [{workflow_runs:[
    run(18; 1; 8; "completed"; $old),
    run(17; 1; 7; "completed"; $old),
    run(16; 1; 6; "completed"; $recent),
    run(15; 1; 5; "in_progress"; $old),
    run(28; 2; 8; "completed"; $old),
    run(27; 2; 7; "queued"; $old)
  ]}, {workflow_runs:[
    run(14; 1; 4; "completed"; $old),
    run(13; 1; 3; "completed"; $old),
    run(12; 1; 2; "completed"; $old),
    run(11; 1; 1; "completed"; $old),
    run(26; 2; 6; "completed"; $old),
    run(25; 2; 5; "completed"; $old)
  ]}]
' > "$work/pages.json"
cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == api ]]
shift
if [[ "$1" == --paginate ]]; then
  cat "$CLEANUP_FIXTURE/pages.json"
elif [[ "$1" == --method ]]; then
  [[ "$2" == DELETE ]]
  printf '%s\n' "${3##*/}" >> "$CLEANUP_FIXTURE/deleted"
else
  run_id=${1##*/}
  jq --argjson id "$run_id" '
    .[].workflow_runs[] | select(.id == $id)
    | if .id == 13 then .status = "in_progress"
      elif .id == 12 then .updated_at = "2999-01-01T00:00:00Z"
      else . end
  ' "$CLEANUP_FIXTURE/pages.json"
fi
MOCK
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" CLEANUP_FIXTURE=$work
export GITHUB_REPOSITORY=example/fixture GH_TOKEN=fixture GITHUB_RUN_ID=25
export RETENTION_DAYS=7 MINIMUM_RUNS=2
DRY_RUN=true bash "$project/ci/cleanup-workflow-runs.sh" > "$work/log"
[[ ! -f "$work/deleted" ]] || fail 'dry run deleted history'
[[ $(awk '/^Would delete run / {count++} END {print count+0}' "$work/log") == 3 ]] || fail 'wrong dry-run candidates'
DRY_RUN=false bash "$project/ci/cleanup-workflow-runs.sh" > "$work/log"
printf '11\n14\n26\n' > "$work/expected"
sort -n "$work/deleted" > "$work/actual"
cmp "$work/expected" "$work/actual" || fail 'retention or rerun protection failed'
if MINIMUM_RUNS=0 bash "$project/ci/cleanup-workflow-runs.sh" > "$work/error" 2>&1; then
  fail 'invalid retention accepted'
fi
printf 'PASS: workflow cleanup respects age, per-workflow history, dry runs and active reruns\n'
)

test_host_tools
test_golang
test_workflow_cleanup

# Generated choices follow source data and leave unrelated workflow steps intact.
(
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  mkdir -p "$work/bin"
  cat > "$work/bin/git" <<'MOCK'
#!/bin/sh
[ "$1" = ls-remote ] || exit 1
printf '%s\n' 'sha refs/tags/v9.9.9' 'sha refs/tags/v10.0.0' 'sha refs/tags/v10.0.0-rc1' 'sha refs/tags/v8.0.0'
MOCK
  chmod +x "$work/bin/git"
  cp "$project/.github/workflows/build.yml" "$work/build.yml"
  PATH="$work/bin:$PATH" bash "$project/ci/sync-build-inputs.sh" "$work/build.yml"
  grep -q '^          - v10.0.0$' "$work/build.yml" || fail 'release choices not generated'
  if grep -q 'v10.0.0-rc1' "$work/build.yml"; then fail 'prerelease included in stable choices'; fi
  [[ $(awk '/          - v/ {print $2}' "$work/build.yml") == $'v10.0.0\nv9.9.9\nv8.0.0' ]] || fail 'release choices not sorted numerically'
  cp "$work/build.yml" "$work/once.yml"
  PATH="$work/bin:$PATH" bash "$project/ci/sync-build-inputs.sh" "$work/build.yml"
  cmp "$work/once.yml" "$work/build.yml" || fail 'choice generation is not idempotent'
  sed '/# BEGIN GENERATED BUILD INPUTS/,/# END GENERATED BUILD INPUTS/d' "$project/.github/workflows/build.yml" > "$work/original"
  sed '/# BEGIN GENERATED BUILD INPUTS/,/# END GENERATED BUILD INPUTS/d' "$work/build.yml" > "$work/generated"
  cmp "$work/original" "$work/generated" || fail 'choice generation changed build steps'
  printf 'PASS: workflow choices follow official stable tags without changing build steps\n'
)
