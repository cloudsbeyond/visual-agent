#!/usr/bin/env bash
# Compile the three runtime scripts into standalone executables under runtimes/desktop-gui/bin/.
#
# Why: each runtime is a `swift` script that recompiles on every invocation. For host integration
# (high-frequency calls), compiling once removes the recompile overhead and the hard dependency on
# `swift` being on PATH at call time. Once bin/ exists, the L2/L3 runners prefer it automatically
# (see "@integration section 9 Compiled Binary Resolution") and fall back to the scripts if it is absent.
#
# Usage: bash runtimes/desktop-gui/scripts/build.sh
# Output: runtimes/desktop-gui/bin/{action_executor,scene_runner,task_flow}

set -eu

RUNTIME_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$RUNTIME_ROOT/src"
BIN="$RUNTIME_ROOT/bin"

mkdir -p "$BIN"

for name in action_executor scene_runner task_flow; do
  echo "compiling $name ..."
  swiftc -O "$SRC/$name.swift" -o "$BIN/$name"
done

echo "built: $BIN/action_executor $BIN/scene_runner $BIN/task_flow"
