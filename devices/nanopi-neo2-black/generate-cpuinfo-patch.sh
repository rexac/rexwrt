#!/usr/bin/env bash
# Generate the model-name change from the detected kernel's source context.
# Original change: Sumit Gupta <sumitg@nvidia.com>, 29 August 2016.
set -euo pipefail
root=${1:?OpenWrt source directory required}
output=${2:?Patch output directory required}
dry_run=${3:-0}
kernel=$(sed -n 's/^KERNEL_PATCHVER:=//p' "$root/target/linux/sunxi/Makefile")
[[ "$kernel" =~ ^[0-9]+\.[0-9]+$ ]] || { echo 'Invalid Sunxi kernel version' >&2; exit 1; }
relative=sunxi/patches-$kernel/312-arm64-cpuinfo-model-name.patch
url=https://raw.githubusercontent.com/torvalds/linux/v$kernel/arch/arm64/kernel/cpuinfo.c
if [[ "$dry_run" == 1 ]]; then
  printf '[DRY] Generate CPU info patch from %s -> %s/%s\n' "$url" "$output" "$relative"
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/before/arch/arm64/kernel" "$work/after/arch/arm64/kernel"
source_file=$work/before/arch/arm64/kernel/cpuinfo.c
curl -fLSs --retry 3 "$url" -o "$source_file"
# Require the complete known statement, so a changed layout cannot be edited silently.
if ! awk '
  { lines[NR]=$0 }
  END {
    for (i=1; i<=NR; i++) {
      if (lines[i] ~ /^[\t ]*if \(compat\)$/ &&
          lines[i+1] ~ /^[\t ]*seq_printf\(m, "model name\\t: ARMv8 Processor rev %d \(%s\)\\n",$/ &&
          lines[i+2] ~ /^[\t ]*MIDR_REVISION\(midr\), COMPAT_ELF_PLATFORM\);$/) {
        count++; remove=i
      }
    }
    if (count != 1) exit 1
    for (i=1; i<=NR; i++) {
      if (i == remove) continue
      line=lines[i]
      if (i == remove+1 || i == remove+2) sub(/^\t/, "", line)
      print line
    }
  }
' "$source_file" > "$work/after/arch/arm64/kernel/cpuinfo.c"; then
  echo "CPU info layout changed in Linux $kernel; review required before generating a patch." >&2
  exit 1
fi
status=0
(cd "$work" && git diff --no-index --no-renames --src-prefix= --dst-prefix= before after) > "$work/change.patch" || status=$?
[[ "$status" == 1 ]] || { echo 'Failed to generate CPU info diff' >&2; exit 1; }
git -C "$work/before" apply --check -p1 "$work/change.patch"
mkdir -p "$output/$(dirname "$relative")"
{
  printf 'From: Sumit Gupta <sumitg@nvidia.com>\n'
  printf 'Subject: [PATCH] arm64: cpuinfo: show model name for 64-bit tasks\n\n'
  printf 'Regenerated against Linux %s from the original model-name change.\n\n' "$kernel"
  cat "$work/change.patch"
} > "$output/$relative"
printf 'Generated CPU info patch for Linux %s\n' "$kernel"
