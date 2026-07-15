# 08 — Compose and Recognize Mentions Interactively

**What to build:** Add accessible mention autocomplete to the existing Message composer and visually distinguish recognized mention syntax in rendered Messages. Suggestions reflect current Workspace membership and the current member's Everyone Mention capability, while manually typed valid syntax remains authoritative when the Message is sent.

**Blocked by:** 07 — Send Role-Gated Everyone Mentions.

**Status:** ready-for-agent

- [ ] Typing an active mention query opens suggestions filtered to current Workspace Members by username.
- [ ] Owners and admins can select `@everyone`; regular members never see it as an actionable option.
- [ ] Keyboard users can move through, select, and dismiss suggestions with appropriate accessible state.
- [ ] Selecting a suggestion inserts the mention without destroying surrounding draft content or reply-composer state.
- [ ] Manually typed valid mentions work without autocomplete and are resolved only by the Chat send workflow.
- [ ] Recognized User Mention and Everyone Mention syntax is visually distinct in live and initially loaded Message rows without changing stored content.
- [ ] Autocomplete, suggestion rows, and rendered mention spans have stable unique IDs suitable for behavior tests.
- [ ] Authenticated Channel LiveView tests cover filtering, role capability, keyboard interaction, manual fallback, and rendering.
- [ ] `mix precommit` passes.
