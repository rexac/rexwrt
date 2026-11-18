#!/usr/bin/env bash
# Use fresh container stores on the build volume of a disposable hosted runner.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && ${RUNNER_ENVIRONMENT:-} == github-hosted && ${RUNNER_OS:-} == Linux ]] || {
  echo 'Docker storage setup requires a disposable GitHub-hosted Linux runner.' >&2
  exit 1
}
: "${GITHUB_WORKSPACE:?}" "${GITHUB_ENV:?}"
build_volume=$GITHUB_WORKSPACE/work
mountpoint -q "$build_volume" || { echo 'The build volume must be mounted first.' >&2; exit 1; }
[[ $(docker info --format '{{.DockerRootDir}}') == /var/lib/docker ]] || {
  echo 'Unexpected Docker data directory; refusing to leave image storage on root.' >&2
  exit 1
}
[[ -z $(docker ps -aq) ]] || { echo 'Docker storage setup must run before creating containers.' >&2; exit 1; }

# Stop socket activation as well as both daemons before mounting empty stores.
# containerd can store image layers outside /var/lib/docker on newer engines.
sudo systemctl stop docker.socket docker.service containerd.service
for store in docker containerd; do
  sudo install -d -m 0711 "$build_volume/.$store" "/var/lib/$store"
  sudo mount --bind "$build_volume/.$store" "/var/lib/$store"
  mountpoint -q "/var/lib/$store"
done
sudo systemctl start containerd.service docker.service
docker info --format 'Docker storage: {{.DockerRootDir}} ({{.Driver}})'
df -h "$build_volume" /var/lib/docker /var/lib/containerd /
printf 'REXWRT_DISPOSABLE_DOCKER=1\n' >> "$GITHUB_ENV"
