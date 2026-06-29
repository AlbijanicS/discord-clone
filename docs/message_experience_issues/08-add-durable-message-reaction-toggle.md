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

- [ ] A migration creates durable message reactions with message, user, emoji,
      and timestamp fields.
- [ ] The migration is generated with `mix ecto.gen.migration`.
- [ ] A unique index prevents duplicate rows for one message, User, and emoji.
- [ ] Message deletion removes related reaction rows.
- [ ] User deletion removes related reaction rows.
- [ ] A Chat-owned reaction schema exists.
- [ ] Chat exposes `toggle_reaction(scope, message_id, emoji)`.
- [ ] Authenticated Workspace Members can add a reaction to an accessible
      message.
- [ ] Toggling the same emoji again removes the current User's reaction.
- [ ] Different Users can react with the same emoji.
- [ ] One User can react with different emoji to the same message.
- [ ] Anonymous scopes are rejected.
- [ ] Logged-in non-members cannot react to inaccessible Workspace messages.
- [ ] Invalid emoji payloads are rejected before durable mutation.
- [ ] Reaction state is not stored in ChannelServer.
- [ ] Focused Chat context tests cover authorization, toggling, uniqueness,
      invalid emoji, and cleanup behavior.

## Blocked by

- 6. Add Minimal Emoji Normalization And Validation
