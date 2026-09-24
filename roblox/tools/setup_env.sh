#!/usr/bin/env bash
# One-shot environment setup for a fresh Linux container (what the Claude Code cloud session used).
# Installs Rojo, StyLua, Selene, Lune, luau-lsp (+ Roblox type definitions) and Blender 5.2 headless.
# Idempotent; safe to re-run. Takes ~10 minutes on first run (cargo builds).
set -euo pipefail

BIN="$HOME/.local/bin"
mkdir -p "$BIN"
export PATH="$BIN:$HOME/.cargo/bin:$PATH"

echo "== Rojo"
if ! command -v rojo >/dev/null 2>&1; then
  curl -sSL -o /tmp/rojo.zip https://github.com/rojo-rbx/rojo/releases/download/v7.7.0/rojo-7.7.0-linux-x86_64.zip
  unzip -o -q /tmp/rojo.zip -d "$BIN" && chmod +x "$BIN/rojo"
fi
rojo --version

echo "== luau-lsp + Roblox type definitions"
if ! command -v luau-lsp >/dev/null 2>&1; then
  curl -sSL -o /tmp/lsp.zip https://github.com/JohnnyMorganz/luau-lsp/releases/download/1.70.0/luau-lsp-linux-x86_64.zip
  unzip -o -q /tmp/lsp.zip -d "$BIN" && chmod +x "$BIN/luau-lsp"
fi
[ -f "$BIN/globalTypes.d.luau" ] || curl -sSL -o "$BIN/globalTypes.d.luau" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
luau-lsp --version

echo "== StyLua, Selene, Lune (cargo)"
command -v cargo >/dev/null 2>&1 || { echo "cargo missing: install rustup first"; exit 1; }
command -v stylua >/dev/null 2>&1 || cargo install stylua --features luau
command -v selene >/dev/null 2>&1 || cargo install selene
command -v lune >/dev/null 2>&1 || cargo install lune
stylua --version; selene --version; lune --version

echo "== Blender 5.2 (headless)"
if [ ! -x /opt/blender/blender ]; then
  F=$(curl -sS https://download.blender.org/release/Blender5.2/ | grep -oE 'blender-5\.2\.[0-9]+-linux-x64\.tar\.xz' | sort -V | uniq | tail -1)
  curl -sSL -o /tmp/blender.tar.xz "https://download.blender.org/release/Blender5.2/$F"
  mkdir -p /opt/blender && tar -xJf /tmp/blender.tar.xz -C /opt/blender --strip-components=1 && rm -f /tmp/blender.tar.xz
fi
/opt/blender/blender -b --version | head -1

echo "== done. Add to PATH: export PATH=\"$BIN:\$HOME/.cargo/bin:\$PATH\"; blender is /opt/blender/blender"
