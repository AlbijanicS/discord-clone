# Add Durable Message Reaction Toggle

**Type:** AFK

**Blocked by:** 6. Add Minimal Emoji Normalization And Validation

**User stories covered:** 19-20, 23-24, 26-28, 30-32, 35, 38

## What to build

Add the durable reaction mutation path. A Workspace Member should be able to
toggle one emoji reaction on an accessible message: the first toggle creates a
reaction row, and the second toggle removes that same User/message/emoji row.
Reaction rows should be Postgres-backed product state and should use Workspace
membership as the access boundary.

This slice should establish the durable model and Chat API without rendering
reaction pills or live refresh behavior yet.

## Acceptance criteria

- [x] A migration creates durable message reactions with message, user, emoji,
      and timestamp fields.
- [x] The migration is generated with `mix ecto.gen.migration`.
- [x] A unique index prevents duplicate rows for one message, User, and emoji.
- [x] Message deletion removes related reaction rows.
- [x] User deletion removes related reaction rows.
- [x] A Chat-owned reaction schema exists.
- [x] Chat exposes `toggle_reaction(scope, message_id, emoji)`.
- [x] Authenticated Workspace Members can add a reaction to an accessible
      message.
- [x] Toggling the same emoji again removes the current User's reaction.
- [x] Different Users can react with the same emoji.
- [x] One User can react with different emoji to the same message.
- [x] Anonymous scopes are rejected.
- [x] Logged-in non-members cannot react to inaccessible Workspace messages.
- [x] Invalid emoji payloads are rejected before durable mutation.
- [x] Reaction state is not stored in ChannelServer.
- [x] Focused Chat context tests cover authorization, toggling, uniqueness,
      invalid emoji, and cleanup behavior.

## Blocked by

- 6. Add Minimal Emoji Normalization And Validation
