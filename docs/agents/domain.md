# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- `CONTEXT.md` at the repo root.
- `docs/adr/` entries relevant to the area being changed.

If any of these files do not exist, proceed silently. Producer skills create them lazily when terms or decisions are resolved.

## File structure

This is a single-context repository:

```text
/
├── CONTEXT.md
├── docs/adr/
└── lib/
```

## Use the glossary's vocabulary

When output names a domain concept in an issue title, specification, refactor proposal, hypothesis, or test name, use the canonical term from `CONTEXT.md`. Do not drift to synonyms the glossary explicitly avoids.

If a necessary concept is absent from the glossary, reconsider whether the term belongs or note the gap for the domain-modeling workflow.

## Flag ADR conflicts

If output contradicts an existing ADR, surface the conflict explicitly rather than silently overriding it.
