---
description: Regenerate the architecture dependency graph
---
Trace dependencies across `backend/app/` (Python imports) and `ios/Riva/` (Swift
module/type usage) and rewrite `vault/ArchitectureGraph.md` as a mermaid dependency graph.
Swift has no textual import graph like Python — infer edges from type usage and the
`App/ Core/ Features/ DesignSystem/ Shared/` layering.
Flag any cycle and any edge that crosses a layer boundary defined in `vault/Architecture.md`.
