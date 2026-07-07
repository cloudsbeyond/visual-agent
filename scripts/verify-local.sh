#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== diff hygiene =="
git diff --check

require_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$file" || {
    echo "missing root authority marker in $file: $expected" >&2
    exit 1
  }
}

reject_contains() {
  local file="$1"
  local forbidden="$2"
  if grep -Fq -- "$forbidden" "$file"; then
    echo "forbidden source-method leakage marker in $file: $forbidden" >&2
    exit 1
  fi
}

echo "== root authority conformance =="
require_contains AGENTS.md "current documentation authority chain has exactly four files"
require_contains AGENTS.md "README.md / README.zh-CN.md / PRD.md"
require_contains AGENTS.md "Product L0"
require_contains AGENTS.md "Protocol L1/L2"
require_contains AGENTS.md "VERIFY_LOCAL_OK"
require_contains README.md "fixed equivalent formal L0 projection"
require_contains README.md '[`PRD.md`](./PRD.md)'
require_contains README.zh-CN.md "PRD.md"
require_contains PRD.md "fixed formal L0 projection"
require_contains PRD.md "## P0 Scope"
require_contains PRD.md "## Downstream Chain"
require_contains PRD.md "## Owner Boundary"
require_contains PRD.md "README.md / README.zh-CN.md / PRD.md"
require_contains protocol/README.md "AGENTS.md"
require_contains protocol/README.md "PRD.md"

echo "== source-method leakage scan =="
for file in AGENTS.md README.md README.zh-CN.md PRD.md protocol/README.md integration/host-embedding.md; do
  reject_contains "$file" "source-side method"
  reject_contains "$file" "execution-context detail"
  reject_contains "$file" "agent-host"
  reject_contains "$file" "source-function"
  reject_contains "$file" "selected workflow"
  reject_contains "$file" "selected skill"
  reject_contains "$file" "target runtime external method"
  reject_contains "$file" "agent runtime external method"
  reject_contains "$file" "runtime dependency on source"
  reject_contains "$file" "devops dependency on source"
  reject_contains "$file" "l0_refs"
  reject_contains "$file" "l1_l2_refs"
  reject_contains "$file" "l3_refs"
  reject_contains "$file" "l4_validation"
done

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
