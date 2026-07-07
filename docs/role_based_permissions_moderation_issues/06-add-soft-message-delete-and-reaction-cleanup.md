# Add Soft Message Delete And Reaction Cleanup

**Type:** AFK

**Blocked by:** 2. Add Owner-Only Role Changes With Audit Log Foundation

**User stories covered:** 47-52, 61, 65

## What to build

Add immediate soft deletion for messages. Authors can delete their own messages
without moderation audit history. Owners and admins can delete allowed target
messages, subject to owner immunity, and moderator deletes are audited.

Deleted messages should remain as placeholders so timeline sequence, unread
behavior, and context remain coherent. Reactions on deleted messages should be
removed, and deleted messages should reject future reactions.

## Acceptance criteria

- [ ] Messages can be soft deleted without removing the durable row.
- [ ] Any user can delete their own message.
- [ ] Own-message deletion is not recorded as a moderation audit event.
- [ ] Owners can delete admin and member messages.
- [ ] Admins can delete admin and member messages, but not owner messages.
- [ ] Moderator message deletion appends an audit event.
- [ ] Deleted messages render as placeholders to viewers.
- [ ] Reactions are removed when a message is deleted.
- [ ] Deleted messages reject future reactions.
- [ ] Message deletion broadcasts enough state for connected channel viewers to
      update.
- [ ] Focused Chat context and LiveView tests cover authorization, placeholders,
      reaction cleanup, audit behavior, and broadcasts.

## Blocked by

- 2. Add Owner-Only Role Changes With Audit Log Foundation
