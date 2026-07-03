# Finalize Unread Ranges Acceptance Coverage

**Type:** AFK

**Blocked by:** 1-19

**User stories covered:** 1-46

## What to build

Run the final acceptance pass for the range-based unread experience. This slice
should close gaps across Chat context behavior, Workspaces lifecycle behavior,
Channel LiveView outcomes, client hook contracts, and project documentation.

The goal is to prove the PRD's end-to-end behavior through public APIs and
observable UI outcomes, then run the project precommit alias.

## Acceptance criteria

- [ ] Chat tests cover sequence assignment, span merge/subtract, visible-read
      validation, send fanout, read actions, landing decisions, and
      sequence-window loading.
- [ ] Workspaces tests cover read-state initialization and cleanup for
      Workspace creation, invite acceptance, Channel creation, and leaving a
      Workspace.
- [ ] Channel LiveView tests cover unread-preserving open, small and large
      unread landings, automatic pagination, read actions, divider behavior,
      sticky actions, sidebar mark-read, and cross-session sync.
- [ ] Channel LiveView tests cover selected-Channel incoming Messages while the
      User is at latest and while the User is reading older history, proving no
      forced scroll or accidental read clear.
- [ ] Channel LiveView and hook tests cover visible-read observation with
      container-rooted visibility, tall Message rows, focus/visibility pauses,
      LiveView patch cleanup, and rendered-window validation.
- [ ] Windowing tests prove the 300-Message cap prunes stream items and all
      per-Message assigns such as row metadata and reaction summaries.
- [ ] Hook behavior is verified at the highest practical level available in
      the project, with small deterministic hooks and server event-contract
      tests where full browser coverage is not present.
- [ ] Tests use stable DOM IDs with `element/2`, `has_element?/2`, and related
      LiveView helpers instead of raw HTML assertions.
- [ ] Documentation reflects that unread spans are canonical and read states
      are summary state.
- [ ] Documentation captures the chosen Chat unread error semantics:
      unauthenticated scopes return `{:error, :unauthenticated}` and logged-in
      non-members return `{:error, :not_found}`.
- [ ] Documentation preserves the unchanged route placement:
      `:browser` pipeline and `live_session :require_authenticated_user`.
- [ ] Existing v1 cursor-unread docs are either clearly superseded or linked to
      the range PRD to avoid implementer confusion.
- [ ] Focused Chat, Workspaces, and Channel LiveView tests pass.
- [ ] `mix precommit` passes.

## Blocked by

- 1. Add Channel-Local Message Sequencing
- 2. Create Unread Span And Read-State Storage
- 3. Backfill Range State From Cursor Reads
- 4. Implement Span Merge And Subtract Workflows
- 5. Create Message Send Unread Fanout
- 6. Initialize And Clean Up Range State From Workspace Workflows
- 7. Expose Read-State Summaries And Private PubSub
- 8. Add Channel Open Landing Decisions
- 9. Add Sequence-Based Message Windows
- 10. Replace Channel Mount With Landing Windows
- 11. Add Explicit Channel Read Actions
- 12. Add Automatic Bidirectional History Loading
- 13. Bound The Rendered Message Window
- 14. Add Visible-Read Observation Hook
- 15. Persist Scroll Anchors From Visible Messages
- 16. Render Unread Divider And Sticky Actions
- 17. Add Sidebar Mark-As-Read Controls
- 18. Sync Read State Across User Sessions
- 19. Retire Cursor-Read Runtime Behavior
