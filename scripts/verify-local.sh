#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== diff hygiene =="
git diff --check

echo "== protocol conformance =="
node --check scripts/verify-protocol-conformance.mjs
node scripts/verify-protocol-conformance.mjs

echo "== adapter syntax =="
node --check adapters/tool-calling/invoke.mjs
node --check adapters/workflow/node.mjs

echo "== desktop GUI runtime typecheck =="
swiftc -typecheck runtimes/desktop-gui/src/action_executor.swift
swiftc -typecheck runtimes/desktop-gui/src/scene_runner.swift
swiftc -typecheck runtimes/desktop-gui/src/task_flow.swift

echo "== shell syntax =="
bash -n runtimes/desktop-gui/scripts/build.sh
bash -n runtimes/desktop-gui/scripts/smoke.sh

echo "== runtime smoke =="
bash runtimes/desktop-gui/scripts/smoke.sh

echo "VERIFY_LOCAL_OK"
