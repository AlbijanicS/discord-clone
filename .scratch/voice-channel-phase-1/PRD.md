# Phase 1: Durable Voice Channels PRD

Status: ready-for-agent

This is the ready-for-agent product artifact for Phase 1 of the Voice Channel
roadmap. It follows the accepted server-routed Voice Channel architecture and
implements durable Workspace state only.

## Problem Statement

Workspaces currently provide durable text Channels, but they have no durable
place to define the audio spaces that the later Voice Channel feature will use.
Without a durable Voice Channel model, Workspace Owners and Admins cannot
prepare or manage audio spaces, Workspace Members cannot see what voice spaces
exist, and later WebRTC work would have no authorized Workspace resource to
join.

The application needs a small, durable Voice Channel lifecycle now, without
prematurely creating a Voice runtime, a signaling transport, a Voice Channel
destination, or any browser media behavior.

## Solution

Add Voice Channels as an independently identified durable Workspace resource.
Voice Channels appear in their own sidebar section and are managed through the
existing Workspace membership and role rules:

- Workspace Owners and Admins can create and rename Voice Channels.
- Workspace Owners can delete Voice Channels.
- Every Workspace Member can list Voice Channels in that Workspace.
- Voice Channel rows are display-only in this phase; they do not navigate or
  join a call.

Voice Channels are intentionally not Conversations. They have no Messages,
read state, unread state, activity items, Chat runtime, or WebRTC runtime in
this phase.

## User Stories

1. As a Workspace Owner, I want to create a Voice Channel, so that my Workspace can define an audio space before voice connectivity exists.
2. As a Workspace Admin, I want to create a Voice Channel, so that I can help organize the Workspace's audio spaces.
3. As a regular Workspace Member, I want to see Voice Channels, so that I know which audio spaces exist in my Workspace.
4. As a Workspace Owner, I want to rename a Voice Channel, so that its name continues to describe its purpose.
5. As a Workspace Admin, I want to rename a Voice Channel, so that I can keep the audio-space list understandable.
6. As a Workspace Owner, I want to delete a Voice Channel, so that obsolete audio spaces can be removed.
7. As a Workspace Admin, I should not be able to delete a Voice Channel, so that destructive Workspace structure changes remain owner-controlled.
8. As a regular Workspace Member, I should not be able to create, rename, or delete Voice Channels, so that Workspace structure follows the existing role policy.
9. As a Workspace Member, I want Voice Channels displayed in their own sidebar section, so that I can distinguish audio spaces from text Channels.
10. As a Workspace Member, I want Voice Channels listed in a stable creation order, so that the sidebar remains predictable without a reordering feature.
11. As a Workspace Member, I want a Voice Channel name normalized like a text Channel name, so that the Workspace uses one consistent naming style.
12. As a Workspace Owner or Admin, I want invalid or duplicate Voice Channel names rejected with field-level feedback, so that I can correct the name in place.
13. As a Workspace Member, I want a Voice Channel named `lobby` to coexist with a text Channel named `lobby`, so that text and audio spaces can use the same understandable label.
14. As a Workspace Member, I should not be able to see Voice Channels in a Workspace I do not belong to, so that Workspace privacy is preserved.
15. As a logged-in non-member, I should not be able to create, rename, or delete a Voice Channel in another Workspace, so that browser actions cannot bypass membership authorization.
16. As an anonymous visitor, I should not be able to access Voice Channel workflows, so that every Voice Channel action is attached to an authenticated User.
17. As a Workspace Owner, I want a deletion confirmation before deleting a Voice Channel, so that I do not remove a durable Workspace resource by accident.
18. As a Workspace Member, I want Voice Channel rows to remain non-interactive for now, so that the sidebar does not imply that a call can already be joined.
19. As a Workspace creator, I do not want a default Voice Channel created automatically, so that each Workspace starts only with its existing text Landing Channel.
20. As a developer, I want Voice Channels to have their own durable identity, so that later Voice Sessions can reference them without inheriting Conversation behavior.
21. As a future Voice-feature implementer, I want no Voice processes or browser media introduced in this phase, so that durable Workspace modeling is proven before WebRTC complexity is added.
22. As a future maintainer, I want the Voice Channel lifecycle to be available through the Workspaces context, so that authorization and persistence stay outside the web layer.

## Implementation Decisions

- Voice Channel is a durable Workspaces resource and remains separate from the
  Conversation hierarchy, as established by the accepted Voice architecture
  decision.
- Add a `voice_channels` relation with an independently generated UUID primary
  key, a required Workspace association, a required name, and UTC timestamps.
- Do not add a `position` field. Voice Channels are ordered by ascending
  creation timestamp and then durable identity for deterministic ties.
- Add a Workspace-to-Voice-Channel association. Voice Channels do not have a
  Conversation association and must not acquire Message, read-state, unread,
  activity, or Chat-runtime associations.
- Reuse the existing Channel name behavior: trim surrounding whitespace,
  lowercase, replace whitespace runs with dashes, require 1–80 characters, and
  permit only lowercase letters, numbers, dashes, and underscores after
  normalization.
- Enforce Voice Channel name uniqueness per Workspace. A Voice Channel name
  may duplicate a text Channel name in the same Workspace.
- Generate the database migration with the project-standard migration task.
- Extend `DiscordClone.Workspaces` with public, scope-first Voice Channel
  workflows matching existing Channel conventions: list, fetch, change for
  forms, create, rename, delete, and capability predicates.
- Each public workflow accepts `current_scope` first where authorization is
  required. The Workspace identifier is the source of Workspace association;
  request attributes must not choose or override it.
- Reuse the established error vocabulary: unauthenticated calls return
  `:unauthenticated`; authenticated non-members return `:unauthorized`; absent
  Workspace or cross-Workspace Voice Channel references return `:not_found`;
  invalid create or rename input returns a tagged Voice Channel changeset.
- Workspace Owners and Admins may create and rename Voice Channels. Only a
  Workspace Owner may delete one. All Workspace Members may list and fetch
  Voice Channels in their own Workspace.
- Keep the role rules behind Workspaces capability helpers rather than checking
  role strings in the web layer.
- Add a separate Voice Channels section to the existing Workspace sidebar
  shell. The section uses its own LiveView stream and stable DOM IDs.
- Mirror the current Channel-management interaction pattern: a create control
  for eligible users, form-backed inline rename, an action menu, and an
  owner-only destructive action with a confirmation prompt.
- Voice Channel rows render as display-only labels in Phase 1. Do not add a
  route, selected Voice Channel state, placeholder page, join action, roster,
  or browser hook.
- Add no default Voice Channel when creating a Workspace. The existing `general`
  text Channel remains the only Landing Channel.
- When a durable mutation succeeds, refresh the Voice Channel sidebar in the
  existing Workspace shell views using the application's established
  Workspace-event and stream-refresh conventions.
- Do not add `ex_webrtc` or any Voice supervision, process registration,
  Phoenix socket/channel signaling, media transport, or browser microphone
  code.
- The existing authenticated Workspace routes remain in the authenticated
  browser pipeline and `:require_authenticated_user` LiveView session because
  these workflows require `current_scope`. No new route is required.

## Testing Decisions

- Good tests prove visible behavior and public Workspaces APIs rather than
  private query construction, implementation helpers, or raw HTML strings.
- The primary seam is the `DiscordClone.Workspaces` public API. Add tests for
  the Voice Channel schema behavior and scoped list/fetch/create/rename/delete
  workflows.
- Context tests should prove name normalization, required and malformed names,
  maximum length, and Voice-Channel-local uniqueness.
- Context tests should prove that a text Channel and Voice Channel may share a
  normalized name in one Workspace.
- Context tests should prove stable creation-order listing and that no position
  behavior exists in this phase.
- Context tests should prove owners and admins can create and rename, only the
  owner can delete, members can list and fetch, non-members are rejected, and
  unauthenticated scopes are rejected.
- Context tests should prove missing Workspaces and cross-Workspace Voice
  Channel identifiers return the project's existing not-found behavior.
- Context tests should prove form workflows receive a changeset through the
  Workspaces context rather than direct schema access from the web layer.
- Add LiveView tests at the existing Workspace shell seam. Assert stable DOM
  IDs and use `element/2`, `has_element?/2`, form helpers, and interaction
  helpers instead of asserting raw rendered HTML.
- LiveView tests should prove the distinct Voice Channels section is visible to
  an authorized Workspace Member and that its rows do not navigate.
- LiveView tests should prove the create control and inline rename affordance
  are visible to owners/admins but absent for regular members.
- LiveView tests should prove the delete action is visible only to an owner,
  includes a confirmation prompt, and removes the Voice Channel after a
  confirmed interaction.
- LiveView tests should prove invalid create and rename submissions retain the
  form and expose field-level errors.
- Reuse existing Workspaces context tests, Workspace fixtures, and Workspace
  LiveView navigation/management tests as prior art.
- Run focused context and LiveView tests during implementation, then run
  `mix precommit` after all changes.

## Out of Scope

- A persisted `position` field, drag-and-drop ordering, or manual reordering.
- A default Voice Channel for new Workspaces.
- Voice Channel routing, a Voice Channel detail page, selection state, or a
  placeholder destination.
- Joining or leaving voice, a voice roster, mute, deafen, speaking state, or
  Voice Owner Tab behavior.
- Browser microphone permissions, JavaScript hooks, WebRTC offers/answers,
  ICE, RTP, ExWebRTC, Phoenix Channel signaling, or any Voice OTP process.
- Messages, read state, unread spans, activity items, or Conversation subtype
  behavior for Voice Channels.
- Voice Channel categories, access overrides, per-Channel permissions, limits,
  moderation behavior, or audit events.
- Workspace Member creation, rename, or deletion authority beyond the settled
  role policy.
- Renaming or deleting the existing text Landing Channel behavior.

## Further Notes

- This spec implements Phase 1 of the Voice Channel roadmap and must preserve
  the durable-versus-runtime boundary in the accepted Voice architecture.
- Voice Channels are durable definitions. Voice Sessions are later runtime-only
  connections and are not created, stored, or inferred here.
- The feature deliberately has two established test seams: the Workspaces
  public API for authorization and durable behavior, and the Workspace LiveView
  for the user-visible sidebar workflow. These seams were reviewed and
  confirmed before publishing.
- The implementation should leave the application free of Voice runtime
  processes. The durable model must be usable without starting any process.
