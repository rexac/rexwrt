#!/usr/bin/env bash
set -euo pipefail
terminal=$OPENWRTROOT/files/root
mkdir -p "$terminal"
git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh "$terminal/.oh-my-zsh"
for plugin in zsh-autosuggestions zsh-syntax-highlighting zsh-completions; do
  git clone --depth 1 "https://github.com/zsh-users/$plugin" "$terminal/.oh-my-zsh/custom/plugins/$plugin"
done
cp "$REXWRT_ROOT/config/zshrc" "$terminal/.zshrc"
sed -i 's|/bin/ash|/usr/bin/zsh|g' "$OPENWRTROOT/package/base-files/files/etc/passwd"
