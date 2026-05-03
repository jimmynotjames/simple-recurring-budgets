---
isolation: none
---

# Claude Code agent instructions

Project-wide agent instructions live in [`AGENTS.md`](../AGENTS.md). Treat that file as canonical for:

- Build and test procedure (four-step: `make format` → `make lint-fix` → `make build` → `make test`)
- Swift 6 concurrency rules (default `@MainActor` isolation, `Sendable` requirements)
- High-level docs to consult (`docs/main-prd.md`, `docs/product-features-planning.md`, `docs/tech-design-doc.md`)
- **Cross-cutting concerns checklist** (accessibility, localized source strings, translations queue, Mixpanel user-action events) — every UI-touching change must address all four per `docs/main-prd.md` §6.8
- Conflicts and planning protocol
- Doc maintenance protocol
- OpenSpec workflow

OpenSpec workflow context (artifact rules, doc-alignment checks, apply/verify/archive expectations) lives in [`openspec/config.yaml`](../openspec/config.yaml).
