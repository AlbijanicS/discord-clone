# Persisted Chat Issues

This document breaks `docs/persisted_chat/prd.md` into thin, independently
grabbable vertical slices. The project is using a docs-first fallback for now,
so these are not published to GitHub Issues.

## 1. Read Recent Channel Messages

**Type:** AFK

**Blocked by:** None - can start immediately

**User stories covered:** 1-4, 8-10, 20-22, 24-25, 27-29, 33-35

## What to build

Add the first complete persisted chat read path for channel entry. A workspace
member opening a channel should see the existing desktop workspace shell and a
real channel message surface instead of the placeholder. The channel surface
should load the latest 50 persisted messages, render them oldest-to-newest,
show each author's username, show a compact server-rendered timestamp, and
render escaped plain-text content.

The Chat context should expose a public recent-message workflow that authorizes
through workspace membership, scopes messages to the selected channel, preloads
authors, and returns the same persisted message shape future send and PubSub
flows will use. Empty channels should show a calm empty state. The shared
workspace shell should keep owning the desktop app frame, while the selected
channel main area is supplied by the channel show LiveView so chat behavior
does not bloat the shell.

## Acceptance criteria

- [ ] The channel page renders the existing workspace and channel shell while
      replacing the "Messages are coming soon" placeholder with a message
      surface.
- [ ] The Chat context exposes a public workflow for loading recent channel
      messages.
- [ ] Recent message loading requires an authenticated workspace member.
- [ ] Anonymous scopes cannot load recent messages.
- [ ] Logged-in non-members cannot load messages for private workspace
      channels.
- [ ] Recent message loading returns only messages from the selected channel.
- [ ] Recent message loading returns at most 50 messages.
- [ ] Returned messages are ordered oldest-to-newest for rendering.
- [ ] Returned messages have their author preloaded.
- [ ] The channel page renders author username, compact timestamp, and escaped
      plain-text content for each message.
- [ ] Empty channels render an empty state instead of the old disabled
      composer placeholder.
- [ ] The shell still supports existing workspace navigation, channel
      navigation, invite action, workspace creation, channel creation, and
      workspace/channel action menus while the message surface is shown.
- [ ] Focused Chat context tests and channel LiveView tests cover the behavior.

## Blocked by

None - can start immediately

## 2. Send Plain-Text Messages From Channel Composer

**Type:** AFK

**Blocked by:** 1. Read Recent Channel Messages

**User stories covered:** 5-16, 21, 23-25, 27-30, 34-35

## What to build

Add the first complete persisted send path. A workspace member in a channel
should see a real single-line message composer. Submitting the composer should
call a public Chat send workflow that validates workspace membership, trims and
validates plain-text content, persists the message in Postgres, preloads the
author, returns the saved message, and inserts it into the sender's current
message stream.

This slice should stay non-live across clients. Other open browsers should not
receive the message until refresh; that behavior belongs to the later PubSub
phase. Invalid content should keep the typed value in the composer and show
field-level errors. Successful sends should clear the composer.

## Acceptance criteria

- [ ] The channel page shows a real single-line message form instead of the
      disabled composer placeholder.
- [ ] The Chat context exposes a public message changeset helper for form
      usage.
- [ ] The Chat context exposes a public send workflow.
- [ ] Sending requires an authenticated workspace member.
- [ ] Anonymous scopes cannot send messages.
- [ ] Logged-in non-members cannot send messages to private workspace
      channels.
- [ ] Sending uses the selected channel identifier rather than trusting hidden
      form data.
- [ ] Message content is trimmed before validation.
- [ ] Blank or whitespace-only content is rejected.
- [ ] Content longer than 4,000 characters is rejected.
- [ ] Invalid content returns an invalid message changeset through the Chat
      workflow.
- [ ] Invalid form submission keeps the typed content visible and renders
      field-level errors.
- [ ] Successful send persists the message in Postgres.
- [ ] Successful send returns the saved message with author preloaded.
- [ ] Successful send inserts the new message into the sender's current
      LiveView stream.
- [ ] Successful send clears the composer form.
- [ ] Refreshing the channel page shows the sent message from Postgres.
- [ ] The slice does not add PubSub broadcasts or cross-client live delivery.
- [ ] Focused Chat context tests and channel LiveView tests cover the behavior.

## Blocked by

- 1. Read Recent Channel Messages

## 3. Load Older Messages With Cursor Pagination

**Type:** AFK

**Blocked by:** 1. Read Recent Channel Messages

**User stories covered:** 17-19, 31-32

## What to build

Add older-history pagination through a simple "Load older" button above the
message stream. The Chat context should expose a public older-message workflow
that uses the oldest currently loaded message as a cursor. The cursor should
use both `inserted_at` and `id` so messages with the same timestamp still page
predictably.

The UI should prepend older messages above the currently loaded messages while
preserving chronological display order. The button should be shown when there
may be older history and hidden once a page smaller than 50 messages is
returned. Do not add infinite scroll, scroll-position preservation, or client
hooks in this slice.

## Acceptance criteria

- [ ] The Chat context exposes a public older-message workflow.
- [ ] Older-message loading requires an authenticated workspace member.
- [ ] Older-message loading uses a cursor based on `inserted_at` and `id`.
- [ ] Older-message loading returns at most 50 messages.
- [ ] Older-message loading does not include the cursor message again.
- [ ] Older-message loading returns messages oldest-to-newest for rendering.
- [ ] Older-message loading returns messages with author preloaded.
- [ ] Pagination handles messages that share the same timestamp without
      duplicates or skipped records.
- [ ] The channel page renders a "Load older" button above the message stream
      when there may be older history.
- [ ] Clicking "Load older" prepends the older messages above the currently
      loaded messages.
- [ ] The "Load older" button is hidden when there is no older page left.
- [ ] Empty channels do not render a load-older action.
- [ ] The slice does not add infinite scroll, auto-scroll, or scroll-position
      preservation hooks.
- [ ] Focused Chat context tests and channel LiveView tests cover the behavior.

## Blocked by

- 1. Read Recent Channel Messages

## 4. Harden Persisted Chat Access And Cascade Behavior

**Type:** AFK

**Blocked by:** 2. Send Plain-Text Messages From Channel Composer

**User stories covered:** 22-26, 28-30

## What to build

Round out the privacy and data-boundary behavior around the persisted chat
surface. The finished read and send flows should consistently protect private
workspace channels, avoid channel leaks, and recover through existing generic
workspace redirects when a user reaches a channel they cannot access.

This slice should also verify that channel deletion removes persisted messages
through the existing database cascade. The product decision for this phase is
that deliberately deleting a channel deletes its conversation history; no
message archive or soft-delete behavior is needed.

## Acceptance criteria

- [ ] Chat read and send workflows consistently require an authenticated
      workspace member.
- [ ] Chat read and send workflows do not expose whether inaccessible private
      channels exist beyond the app's existing generic access recovery.
- [ ] Messages from one channel never appear in another channel's history.
- [ ] Sending to one channel never creates a message in another channel.
- [ ] Channel access failures from the channel page redirect to the workspace
      index with a generic access flash.
- [ ] Deleting a channel removes its persisted messages through the existing
      database cascade.
- [ ] Deleting one channel does not remove messages from other channels.
- [ ] Message authors may remain nil only according to existing database
      foreign-key behavior; normal send flows always attach the authenticated
      user.
- [ ] Focused Chat context tests and channel LiveView tests cover the behavior.

## Blocked by

- 2. Send Plain-Text Messages From Channel Composer

## 5. Finalize Phase 5 Acceptance Coverage

**Type:** AFK

**Blocked by:** 2. Send Plain-Text Messages From Channel Composer, 3. Load Older Messages With Cursor Pagination, 4. Harden Persisted Chat Access And Cascade Behavior

**User stories covered:** 1-35

## What to build

Finish the persisted chat phase with an end-to-end acceptance sweep. A
workspace member should be able to enter a channel, read recent messages, send
a plain-text message, see it locally, refresh and see it from Postgres, and
load older history. The implementation should remain intentionally non-live
across clients so the next PubSub phase has a clean boundary.

This slice should also clean up any remaining placeholder copy from the channel
surface, make sure deferred polish items remain documented, and run the full
project precommit alias.

## Acceptance criteria

- [ ] A workspace member can open a channel and see the message surface inside
      the existing desktop shell.
- [ ] A workspace member can send a message and see it immediately in their
      current LiveView.
- [ ] Refreshing the channel page shows the sent message from Postgres.
- [ ] Loading older messages works after recent messages have loaded.
- [ ] Invalid message content shows useful validation feedback.
- [ ] Another open browser/session does not receive the message live before
      refresh in this phase.
- [ ] No PubSub subscription or broadcast behavior is introduced.
- [ ] No ChannelServer or OTP-backed channel state is introduced.
- [ ] Deferred polish items remain documented for after persisted chat and
      PubSub are complete.
- [ ] Focused Chat context tests pass.
- [ ] Focused channel LiveView tests pass.
- [ ] The project precommit alias passes.

## Blocked by

- 2. Send Plain-Text Messages From Channel Composer
- 3. Load Older Messages With Cursor Pagination
- 4. Harden Persisted Chat Access And Cascade Behavior
