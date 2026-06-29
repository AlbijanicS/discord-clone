# Add Fixed Reaction Palette Controls

**Type:** AFK

**Blocked by:** 10. Render Reaction Pills Under Messages

**User stories covered:** 18-20, 22, 30

## What to build

Add a small fixed reaction palette to message rows so Workspace Members can
react quickly. The UI should expose only the v1 palette, while the backend
continues to validate reaction emoji through the Chat-owned emoji module.

This slice should wire user clicks to the existing Chat toggle API, but it does
not need to solve cross-view live refresh yet.

## Acceptance criteria

- [ ] Message rows expose a small fixed reaction palette.
- [ ] The palette includes a familiar v1 set such as thumbs up, heart, laugh,
      party, and eyes.
- [ ] Palette controls are visually subtle and do not clutter the default
      timeline.
- [ ] Palette controls have stable DOM IDs for tests.
- [ ] Palette controls include accessible labels.
- [ ] Clicking a palette control calls the Chat reaction toggle workflow.
- [ ] Invalid client payloads still fail through backend validation.
- [ ] Focused LiveView tests verify that a visible palette control can toggle a
      reaction for the current User.

## Blocked by

- 10. Render Reaction Pills Under Messages
