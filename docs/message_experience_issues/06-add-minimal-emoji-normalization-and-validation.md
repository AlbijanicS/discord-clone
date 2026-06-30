# Add Minimal Emoji Normalization And Validation

**Type:** AFK

**Blocked by:** None - can start immediately

**User stories covered:** 17, 30, 34

## What to build

Add a small Chat-owned emoji module that normalizes and validates reaction
emoji payloads. The first validation policy should accept exactly one trimmed,
normalized grapheme and reject blank, oversized, or malformed values. This
keeps the reaction model flexible while the UI exposes only a fixed palette.

This slice should not add reaction storage, shortcode rendering, or UI changes.

## Acceptance criteria

- [x] A small Chat-owned emoji module exposes normalization and validation
      behavior.
- [x] Trimming and normalization are applied consistently.
- [x] Blank values are rejected.
- [x] Oversized values are rejected.
- [x] Values with more than one grapheme are rejected for reaction validation.
- [x] Direct Unicode emoji input can validate when it is one grapheme.
- [x] The module does not add a full Unicode emoji database.
- [x] Focused unit tests cover valid emoji, trimming, blank input, oversized
      input, and multi-grapheme rejection.

## Blocked by

None - can start immediately.
