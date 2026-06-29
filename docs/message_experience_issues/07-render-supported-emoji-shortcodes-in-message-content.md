# Render Supported Emoji Shortcodes In Message Content

**Type:** AFK

**Blocked by:** 6. Add Minimal Emoji Normalization And Validation

**User stories covered:** 14-17, 34

## What to build

Render a tiny allowlist of emoji shortcodes in message content. A Workspace
Member should be able to type common shortcodes such as `:thumbsup:` or
`:heart:` and see them rendered as emoji in the timeline, while unsupported
shortcodes remain unchanged.

Message content should still be stored as typed. Shortcode parsing is a safe
rendering concern for v1, not persisted token metadata.

## Acceptance criteria

- [ ] The emoji module exposes shortcode parsing for a small explicit allowlist.
- [ ] Supported shortcodes render as emoji in Channel message content.
- [ ] Unknown shortcodes remain plain text.
- [ ] Direct Unicode emoji in messages remains visible.
- [ ] Message content is still persisted as the User typed it.
- [ ] Rendering remains safe for HEEx and does not introduce raw HTML risks.
- [ ] Focused emoji tests cover supported shortcode replacement and unknown
      shortcode passthrough.
- [ ] Focused LiveView tests verify supported shortcode rendering through stable
      selectors.

## Blocked by

- 6. Add Minimal Emoji Normalization And Validation
