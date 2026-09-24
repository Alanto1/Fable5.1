#!/usr/bin/env bash
# Lint, format-check and type-check the Luau sources, then build the place file.
set -euo pipefail
cd "$(dirname "$0")/.."

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

echo "== stylua --check"
stylua --check src tests 2>&1 | tail -20

echo "== selene"
if [ ! -f roblox.yml ] && [ ! -f roblox.toml ]; then
  selene generate-roblox-std >/dev/null 2>&1 || echo "(could not generate roblox std; selene will use cached std if present)"
fi
selene src tests 2>&1 | tail -40

if command -v luau-lsp >/dev/null 2>&1 && [ -f "$HOME/.local/bin/globalTypes.d.luau" ]; then
  echo "== luau-lsp analyze"
  rojo sourcemap default.project.json -o sourcemap.json
  luau-lsp analyze --defs="$HOME/.local/bin/globalTypes.d.luau" --base-luaurc=.luaurc --sourcemap=sourcemap.json src
fi

echo "== lune tests"
lune run tests/run.luau

echo "== rojo build"
mkdir -p build
rojo build default.project.json -o build/RaidABase.rbxl
ls -la build/RaidABase.rbxl
