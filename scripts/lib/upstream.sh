#!/usr/bin/env bash
# Resolve moving branches once, then read immutable files for this build.
upstream_die() { printf 'rexwrt upstream: %s\n' "$*" >&2; exit 1; }
upstream_head() {
  local repo=$1 branch=$2 dest=$3 sha= attempt
  for attempt in 1 2 3; do
    if sha=$(git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=30 ls-remote --exit-code "https://github.com/$repo.git" "refs/heads/$branch" | awk '{print $1}'); then break; fi
  done
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || upstream_die "Cannot resolve $repo:$branch"
  jq -n --arg sha "$sha" '{sha:$sha}' > "$dest"
  printf '%s\t%s\t%s\n' "$repo" "$branch" "$sha" >> "$UPSTREAM_MANIFEST"
  printf '%s\n' "$sha"
}
upstream_file() {
  local repo=$1 ref=$2 path=$3 dest=$4 code status=0 mirror cache=
  mkdir -p "$(dirname "$dest")"
  if [[ -n "${REXWRT_UPSTREAM_CACHE:-}" ]]; then
    cache=$REXWRT_UPSTREAM_CACHE/$repo/$ref/$path
    if [[ -f "$cache" ]]; then cp "$cache" "$dest"; return 0; fi
    [[ ! -f "$cache.missing" ]] || return 1
  fi
  code=$(curl -LSs --retry 2 --connect-timeout 10 --max-time 30 -w '%{http_code}' \
    "https://raw.githubusercontent.com/$repo/$ref/$path" -o "$dest.tmp") || status=$?
  # Use kernel.org's official Git mirror when GitHub throttles Linux files.
  if [[ ( "$repo" == torvalds/linux || "$repo" == gregkh/linux ) && ( "$code" != 200 && "$code" != 404 ) ]]; then
    mirror=torvalds
    [[ "$repo" != gregkh/linux ]] || mirror=stable
    code=$(curl -LSs --retry 3 --connect-timeout 20 --max-time 120 -w '%{http_code}' \
      "https://kernel.googlesource.com/pub/scm/linux/kernel/git/$mirror/linux/+/$ref/$path?format=TEXT" -o "$dest.base64") || status=$?
    if [[ "$code" == 200 ]]; then
      base64 -d < "$dest.base64" > "$dest.tmp" || upstream_die 'Invalid Linux mirror response'
      status=0
    fi
    rm -f "$dest.base64"
  fi
  if [[ "$code" == 404 && "$status" == 0 ]]; then
    rm -f "$dest.tmp"
    if [[ -n "$cache" ]]; then mkdir -p "$(dirname "$cache")"; : > "$cache.missing"; fi
    return 1
  fi
  [[ "$status" == 0 && "$code" == 200 ]] || upstream_die "Cannot download $repo:$ref/$path (HTTP $code, curl $status)"
  mv "$dest.tmp" "$dest"
  if [[ -n "$cache" ]]; then mkdir -p "$(dirname "$cache")"; cp "$dest" "$cache.tmp.$$"; mv "$cache.tmp.$$" "$cache"; fi
}
upstream_required_file() {
  upstream_file "$@" || upstream_die "Missing upstream file: $1:$2/$3"
}
upstream_setting() {
  local file=$1 name=$2 value
  value=$(sed -nE "s/^[[:space:]]*(declare -g )?${name}=['\"]([^'\"]*)['\"].*$/\\2/p" "$file")
  [[ -n "$value" && "$value" != *$'\n'* ]] || upstream_die "Cannot read a unique $name from $file"
  printf '%s\n' "$value"
}
upstream_tree() {
  curl -fLSs --retry 3 --connect-timeout 20 --max-time 120 \
    "https://api.github.com/repos/$1/git/trees/$2?recursive=1" -o "$3"
  jq -e '.truncated == false and (.tree | type == "array")' "$3" >/dev/null || upstream_die "Incomplete source tree for $1"
}
