#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/source/target/linux/sunxi"
cat > "$work/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
while (( $# )); do
  case "$1" in
    https://*) printf '%s\n' "$1" > "$CPUINFO_URL_LOG" ;;
    -o) cp "$CPUINFO_FIXTURE" "$2"; shift ;;
  esac
  shift
done
MOCK
chmod +x "$work/bin/curl"
export PATH="$work/bin:$PATH"
export CPUINFO_FIXTURE=$work/cpuinfo.c CPUINFO_URL_LOG=$work/url
fail() { echo "FAIL: $*" >&2; exit 1; }
for kernel in 6.6 6.12 6.18 7.4; do
  printf 'KERNEL_PATCHVER:=%s\n' "$kernel" > "$work/source/target/linux/sunxi/Makefile"
  # Linux 6.18 moved the statement into a separate function with less indentation.
  indent=$'\t\t'
  [[ "$kernel" != 6.18 && "$kernel" != 7.4 ]] || indent=$'\t'
  {
    printf '/* Source context for Linux %s */\n' "$kernel"
    printf '%sif (compat)\n' "$indent"
    printf '%s\tseq_printf(m, "model name\\t: ARMv8 Processor rev %%d (%%s)\\n",\n' "$indent"
    printf '%s\t\t   MIDR_REVISION(midr), COMPAT_ELF_PLATFORM);\n' "$indent"
    printf '\n'
  } > "$CPUINFO_FIXTURE"
  bash "$root/devices/nanopi-neo2-black/generate-cpuinfo-patch.sh" "$work/source" "$work/output" > "$work/log"
  patch_file=$work/output/sunxi/patches-$kernel/312-arm64-cpuinfo-model-name.patch
  [[ -s "$patch_file" ]] || fail "$kernel patch destination"
  grep -Fx "https://raw.githubusercontent.com/torvalds/linux/v$kernel/arch/arm64/kernel/cpuinfo.c" "$work/url" >/dev/null
  mkdir -p "$work/tree/arch/arm64/kernel"
  cp "$CPUINFO_FIXTURE" "$work/tree/arch/arm64/kernel/cpuinfo.c"
  git -C "$work/tree" apply "$patch_file"
  if grep -q 'if (compat)' "$work/tree/arch/arm64/kernel/cpuinfo.c"; then fail "$kernel guard remains"; fi
  grep -F 'seq_printf(m, "model name' "$work/tree/arch/arm64/kernel/cpuinfo.c" >/dev/null
  [[ ! -d "$work/output/generic" ]] || fail 'unrelated generic patches generated'
done
printf 'unknown source layout\n' > "$CPUINFO_FIXTURE"
if bash "$root/devices/nanopi-neo2-black/generate-cpuinfo-patch.sh" "$work/source" "$work/invalid" > "$work/error" 2>&1; then
  fail 'unknown layout accepted'
fi
[[ ! -e "$work/invalid" ]] || fail 'unknown layout installed a patch'
grep -q 'review required' "$work/error" || fail 'unknown layout diagnostic'
echo 'PASS: CPU info patches follow detected versions and source indentation; unknown layouts fail safely'
