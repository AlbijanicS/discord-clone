# Create Message Send Unread Fanout

**Type:** AFK

**Blocked by:** 1. Add Channel-Local Message Sequencing, 4. Implement Span Merge And Subtract Workflows

**User stories covered:** 10-11, 15-16, 24, 36-41, 46

## What to build

Update message sending so each persisted Message creates unread state for the
Channel recipients while keeping the sender's own backlog unchanged. Recipient
selection should live behind one Chat-owned boundary so future private Channels
or permissions can replace it without rewriting the send workflow.

This slice keeps fanout synchronous and transactional for now, while isolating
the boundary that can later move to a durable outbox or worker.

## Acceptance criteria

- [ ] Sending a Message inserts the Message, assigns its Channel sequence, and
      creates unread state in one transaction.
- [ ] Channel recipients are all current Workspace Members for the Channel's
      Workspace except the sender.
- [ ] Recipient selection is hidden behind one internal boundary.
- [ ] The sender's Message is never unread for the sender.
- [ ] Sending a Message does not clear the sender's older unread spans.
- [ ] Incoming Messages in the selected Channel create unread state first.
- [ ] Incoming selected-Channel Messages do not rely on "selected Channel"
      suppression; visible observation or explicit dismissal clears them later.
- [ ] Recipient unread spans merge with adjacent or overlapping existing spans.
- [ ] Recipient read-state summaries update transactionally.
- [ ] Message and workspace PubSub broadcasts happen only after the Message,
      sequence, and unread fanout transaction succeeds.
- [ ] Workspace or Channel message broadcasts do not include private unread
      summaries.
- [ ] ChannelServer remains responsible only for temporary runtime state such
      as recent cache and typing users.
- [ ] Focused Chat tests cover recipients, sender exclusion, older sender
      backlog, summary updates, post-commit broadcast behavior, and shared
      broadcast payload privacy.

## Blocked by

- 1. Add Channel-Local Message Sequencing
- 4. Implement Span Merge And Subtract Workflows
