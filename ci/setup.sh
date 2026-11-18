#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source /etc/os-release
packages=$root/ci/dependencies/ubuntu-$VERSION_ID.txt
[[ -f "$packages" ]] || { echo "Unsupported CI host: $PRETTY_NAME" >&2; exit 1; }
sudo apt-get update
# Files contain whitespace-separated package names, no shell expressions.
mapfile -t dependencies < <(awk '{ for (i=1; i<=NF; i++) print $i }' "$packages")
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${dependencies[@]}"
