#!/usr/bin/env bash
# Exercise pagination, retention and concurrent reruns without GitHub mutations.
set -euo pipefail
project=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
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
