# Adapters

Adapters are thin mappings between a Host transport or orchestration surface and the visual-agent
runtime boundary. They are not the product core and they do not call models, plan autonomously, or
judge task success.

Implemented adapter surfaces:

| Tier | Directory | Purpose |
|---|---|---|
| T1 | `tool-calling/` | Maps one Host tool/function call to one desktop GUI `task_flow execute-json` invocation. |
| T2 | `workflow/` | Maps one workflow/DAG node to desktop GUI `preview-json` or `execute-json`. |

The desktop GUI reference runtime lives under `../runtimes/desktop-gui/`. Future browser, mobile,
physical-panel, or embodied-control runtimes may add their own adapters only when they preserve the
same L0/L1/L2/L3 contract.

Future service/MCP adapter notes live under `../docs/future-adapters/`; they are not implemented
adapter surfaces.
