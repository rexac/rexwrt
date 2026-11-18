#!/usr/bin/env bash
# Keep recent history and a minimum per workflow, including retired workflows.
set -euo pipefail
: "${GITHUB_REPOSITORY:?}" "${GH_TOKEN:?}"
retention_days=${RETENTION_DAYS:-30}
minimum_runs=${MINIMUM_RUNS:-20}
dry_run=${DRY_RUN:-false}
[[ "$retention_days" =~ ^[1-9][0-9]{0,3}$ && "$minimum_runs" =~ ^[1-9][0-9]{0,3}$ ]] || {
  echo 'Retention days and minimum runs must be positive integers of at most four digits.' >&2
  exit 1
}
[[ "$dry_run" == true || "$dry_run" == false ]] || { echo 'DRY_RUN must be true or false.' >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cutoff=$(jq -n --argjson days "$retention_days" 'now - ($days * 86400)')
endpoint=repos/$GITHUB_REPOSITORY/actions/runs

# Collect every page before deletion so shrinking result sets cannot skip pages.
gh api --paginate --slurp "$endpoint?per_page=100" > "$work/pages.json"
jq -r --argjson cutoff "$cutoff" --argjson keep "$minimum_runs" --arg current "${GITHUB_RUN_ID:-}" '
  [.[].workflow_runs[]] | group_by(.workflow_id)[]
  | sort_by(.run_number) | reverse | .[$keep:][]
  | select(.status == "completed" and (.id | tostring) != $current)
  | select((.updated_at | fromdateiso8601) < $cutoff)
  | .id
' "$work/pages.json" > "$work/candidates"

deleted=0
while IFS= read -r run_id; do
  # A previously completed run may have been rerun since the initial listing.
  gh api "$endpoint/$run_id" > "$work/run.json"
  if ! jq -e --argjson cutoff "$cutoff" '
    .status == "completed" and ((.updated_at | fromdateiso8601) < $cutoff)
  ' "$work/run.json" >/dev/null; then
    printf 'Skipping changed run %s\n' "$run_id"
    continue
  fi
  if [[ "$dry_run" == true ]]; then
    printf 'Would delete run %s\n' "$run_id"
  else
    gh api --method DELETE "$endpoint/$run_id"
    printf 'Deleted run %s\n' "$run_id"
    deleted=$((deleted + 1))
  fi
done < "$work/candidates"
printf 'Cleanup finished: %s deleted; dry run: %s\n' "$deleted" "$dry_run"
