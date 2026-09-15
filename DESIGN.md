# Graphite Design System

The workspace uses a dark, low-distraction collaboration surface. The visual system lives in [`assets/css/app.css`](assets/css/app.css), while shared Phoenix markup primitives live in `DiscordCloneWeb.CoreComponents`.

## Tokens

- `--graphite-*` names the Graphite palette. Use its semantic surfaces (`rail`, `sidebar`, `canvas`, `panel`, `input`) instead of literal colors.
- `--graphite-on-accent` is the foreground for Graphite accent surfaces and primary actions.
- `--graphite-nav-hover` and `--graphite-nav-active` are navigation-only state surfaces. Do not use them for passive roster or content areas.
- `--graphite-control-radius` is the compact radius for navigation rows, message rows, and composer controls.
- `--conversation-inline` aligns the channel header, message list, typing status, and composer. It contracts at the narrow layout breakpoint.

## Shared Components

`DiscordCloneWeb.CoreComponents` owns the reusable button, input, icon, flash, and modal primitives. Screen-specific LiveViews compose those components rather than creating a parallel component library.

## Interaction Rules

Only actionable navigation rows receive the navigation hover token. Passive content, including the voice-channel roster, remains visually stable on hover. Selected navigation uses the active token; primary actions use the accent surface with `--graphite-on-accent` text.
