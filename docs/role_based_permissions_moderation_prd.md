# Role-Based Permissions And Moderation PRD

Status: draft

## Problem Statement

The Discord clone currently gates most workspace and channel behavior on simple
workspace membership. That was enough for the first durable chat loop, but it is
now too broad: regular members can perform management actions that should belong
to staff, and future features such as uploads, voice simulation, private
channels, moderation, and invite control need a clearer permission boundary.

The project needs a role and moderation system that feels Discord-like without
turning into arbitrary per-user permission editing yet. The system should give
owners and admins fast moderation tools from both the member sidebar and the
chat timeline, keep regular members focused on using channels, and preserve
durable audit history for owner review.

## Solution

Add a workspace-scoped role and moderation system centered on three canonical
roles: `owner`, `admin`, and `member`.

Roles define fixed capabilities for this slice. Owners retain full authority and
exclusive access to workspace-level identity/destructive controls. Admins can
operate day-to-day moderation and channel setup, but cannot manage roles, delete
channels, manage the workspace itself, or moderate the owner. Members can use
channels and delete their own messages.

Moderation actions should be available from both the right-side member list and
message-context interactions in chat. Kicks and bans require reasons and
confirmation. Mutes apply immediately with optional reasons. Timeouts apply
immediately after selecting a fixed duration. Moderator message deletion is an
immediate soft delete with audit history. Author message deletion is an
immediate soft delete without moderation audit history.

Add durable active moderation state, durable bans, and an append-only audit log.
Timeout expiry should be scheduled through the workspace runtime for responsive
UI updates, while database timestamps remain the source of truth. Add a simple
owner-only audit log surface so moderation history is inspectable in the app.

## User Stories

1. As a workspace owner, I want `owner`, `admin`, and `member` to be the canonical roles, so that permissions are easy to understand and test.
2. As a workspace owner, I want to promote members to admins, so that trusted users can help moderate the workspace.
3. As a workspace owner, I want to demote admins to members, so that I can remove staff powers without removing the user from the workspace.
4. As a workspace owner, I want role changes to be owner-only, so that admins cannot escalate or reshuffle authority.
5. As a workspace owner, I want to rename and delete the workspace, so that top-level workspace identity remains under my control.
6. As an admin, I want workspace rename and delete actions to be unavailable to me, so that I cannot accidentally change or destroy the whole workspace.
7. As an owner, I want to create, rename, and delete channels, so that I can fully manage workspace structure.
8. As an admin, I want to create and rename channels, so that I can help organize the workspace.
9. As an admin, I do not want channel deletion available to me, so that destructive channel operations stay owner-only.
10. As a member, I want channel management actions hidden from me, so that my UI stays focused on participating.
11. As an owner or admin, I want to create invite links, so that trusted staff can invite people.
12. As a member, I should not be able to create invite links, so that workspace entry stays staff-controlled.
13. As a banned user, I want invites to appear generically unavailable with no accept option, so that banned access is blocked without exposing moderation details.
14. As an owner, I want to mute admins or members, so that I can stop participation without removing access.
15. As an admin, I want to mute admins or members, so that I can respond quickly to disruptive behavior.
16. As a moderator, I want mute to apply immediately, so that low-risk moderation is fast.
17. As a moderator, I want mute reasons to be optional, so that I can add context when useful without slowing every action.
18. As a muted user, I want to retain read access, so that mute is a participation lock rather than removal.
19. As a muted user, I should not be able to send messages, react, type, upload files later, or join simulated voice later, so that mute consistently blocks participation.
20. As an owner, I want to timeout admins or members with fixed durations, so that temporary discipline is easy to apply.
21. As an admin, I want to timeout admins or members, so that I can temporarily stop participation.
22. As a moderator, I want timeout duration presets of 5 minutes, 1 hour, 24 hours, and 7 days, so that I can choose common durations quickly.
23. As a timed-out user, I want the UI to update immediately, so that I know participation actions are blocked.
24. As a timed-out user, I want my UI to re-enable automatically when the timeout expires, so that I do not need to refresh.
25. As an owner, I want timeout expiry to be audited, so that moderation history includes the full lifecycle.
26. As a developer, I want timeout expiry scheduled by the workspace runtime and backed by database checks, so that live behavior is responsive without making runtime state the source of truth.
27. As a moderator, I want mute and timeout to be able to coexist, so that removing one restriction does not accidentally remove another.
28. As a muted and timed-out user, I want timeout expiry to leave mute active, so that the remaining restriction is respected.
29. As an admin who is muted or timed out, I should retain admin authority, so that participation restrictions do not silently demote staff powers.
30. As an owner, I want to kick admins or members with a required reason, so that removal from the workspace is accountable.
31. As an admin, I want to kick members with a required reason, so that I can remove disruptive members.
32. As an admin, I should not be able to kick another admin, so that admins cannot remove each other from the workspace.
33. As a kicked user, I should lose access immediately but be able to rejoin with a valid invite, so that kick remains distinct from ban.
34. As a kicked user, I want my historical messages preserved, so that conversation history remains intact.
35. As an owner, I want to ban admins or members with a required reason, so that severe removal is accountable.
36. As an admin, I want to ban members with a required reason, so that I can block disruptive members from returning.
37. As an admin, I should not be able to ban another admin, so that ban remains stricter than mute or timeout.
38. As a banned user, I should lose workspace access immediately and be unable to rejoin by invite, so that bans are durable exclusions.
39. As an owner or admin banning a member, I want fixed message cleanup options, so that harmful recent content can be removed during the ban flow.
40. As an owner, I want an all-message cleanup option during ban, so that I can remove all of a banned user’s workspace messages when necessary.
41. As an admin, I should not have the all-message cleanup option, so that the most destructive cleanup stays owner-only.
42. As an unbanned user, I should not automatically regain membership, so that restored access still requires a fresh invite.
43. As an unbanned user who rejoins, I should return as a regular member, so that stale admin status is not restored.
44. As an owner, I want to unban users, so that I can restore eligibility to rejoin.
45. As an admin, I should not be able to unban users, so that ban reversal stays owner-controlled.
46. As an owner, I should be immune from all moderation by admins, so that top authority cannot be suppressed.
47. As an admin, I should not be able to mute, timeout, kick, ban, or delete owner messages, so that owner immunity is consistent.
48. As any user, I want to delete my own messages immediately, so that I can clean up my own content.
49. As an owner or admin, I want to delete allowed target messages immediately from chat, so that moderation can happen where harmful content appears.
50. As a moderator deleting a message, I want the delete to be a soft delete, so that history and auditability are preserved.
51. As any viewer, I want deleted messages to remain as placeholders, so that conversation sequence and unread behavior remain coherent.
52. As any viewer, I do not want reactions left on deleted messages, so that deleted content is fully cleared from visible interaction.
53. As a regular member, I should not see another user’s mute or timeout state, so that moderation details are not socially exposed.
54. As the affected user, I want to see my own muted or timed-out state, so that I understand why participation controls are disabled.
55. As an owner or admin, I want to see active moderation state where I can act on it, so that I can unmute or remove timeouts.
56. As a regular member, I want to see the member list, so that the workspace still feels alive.
57. As a workspace user, I want online owners, admins, and members grouped separately, with offline users in a combined offline list, so that the sidebar feels Discord-like.
58. As a moderator, I want the same allowed actions from the member list and from chat message context menus, so that I do not need to hunt through the sidebar during an incident.
59. As a moderator banning from a message, I want the ban confirmation to include reason and cleanup choices, so that I can act from the relevant message.
60. As a moderator kicking from a message or member row, I want a confirmation with a required reason, so that accidental removals are avoided.
61. As an owner, I want moderation actions to appear only in an owner-only audit log and not as channel system messages, so that channels stay clean.
62. As an owner, I want a simple audit log screen, so that I can inspect moderation and role history.
63. As an admin, I want immediate success or error feedback after my moderation actions, so that I know the action completed even though I cannot view the audit log.
64. As a kicked or banned user with an open workspace session, I want to be redirected away promptly, so that the UI matches my access state.
65. As another workspace viewer, I want member lists and deleted messages to update live after moderation, so that the workspace stays consistent.
66. As a developer, I want authorization expressed through capability checks rather than role comparisons scattered through LiveViews, so that future permissions can evolve safely.
67. As a developer, I want role, moderation, ban, audit, message delete, invite, unread, and presence behavior covered at public context and LiveView boundaries, so that the feature is safe to split into implementation issues.

## Implementation Decisions

- Keep `member` as the lowest stored role name. Do not rename it to `user`, because `user` already means an account and `member` means a workspace relationship.
- Add `admin` as a valid workspace membership role.
- Keep role storage on workspace memberships.
- Use fixed role capabilities for this slice. Do not build arbitrary per-user permission toggles yet.
- Design public authorization around named capabilities such as viewing a workspace, creating invites, managing channels, deleting channels, managing roles, moderating users, deleting messages, and viewing audit history.
- Keep LiveViews behind public context APIs. LiveViews should not directly query role, moderation, or ban tables for authorization decisions.
- Owner capabilities:
  - promote members to admin
  - demote admins to member
  - create invite links
  - rename and delete the workspace
  - create, rename, and delete channels
  - mute and timeout admins or members
  - kick admins or members
  - ban admins or members
  - unban users
  - delete admin/member messages and own messages
  - view the audit log
- Admin capabilities:
  - create invite links
  - create and rename channels
  - mute and timeout admins or members
  - remove mute and timeout from admins or members
  - kick members only
  - ban members only
  - delete admin/member messages and own messages
- Member capabilities:
  - view, read, send to, react in, and use accessible channels when not muted or timed out
  - delete own messages
- Owner immunity is absolute for this slice. Admins cannot mute, timeout, kick, ban, demote, delete owner messages, or otherwise moderate the owner.
- Owners cannot be muted or timed out in any shape for this slice.
- Muted and timed-out admins retain admin authority. Mute and timeout block participation, not staff authority.
- Mute and timeout are workspace-wide.
- Mute and timeout can both be active for the same user.
- Either active mute or active timeout blocks sending messages, reactions, typing, uploads later, and simulated voice participation later.
- Mutes have optional reasons.
- Timeouts use fixed presets: 5 minutes, 1 hour, 24 hours, and 7 days.
- Natural timeout expiry must be audited.
- Timeout expiry should be scheduled by the workspace runtime when a timeout is created and when the runtime starts with active future timeouts.
- Database timestamps remain the source of truth for timeout enforcement and runtime recovery.
- Manual timeout removal should cancel or supersede scheduled timeout expiry.
- Kick requires a reason and confirmation.
- Kick deletes membership and active moderation state, removes read/unread state, removes presence access when applicable, preserves messages, and allows future rejoin by valid invite.
- Ban requires a reason and confirmation.
- Ban deletes membership and active moderation state, removes read/unread state, removes presence access when applicable, creates a durable ban record, and blocks future invite acceptance.
- Ban targets current members only in this slice. Do not add a ban-by-email or ban-by-username screen.
- Unban removes the ban only. It does not restore membership or role.
- Users who rejoin after kick or unban join as regular members unless the owner promotes them again.
- Ban message cleanup options are fixed: none, last 1 hour, last 24 hours, last 7 days, and all workspace messages.
- The all workspace messages cleanup option is owner-only.
- Ban cleanup uses soft deletion for messages.
- Invite creation is fixed to owner/admin. Do not expose an editable invite policy in this slice.
- Banned users should see generic invite unavailable copy and no accept option. Accept endpoints must still reject banned users.
- Add active moderation storage separate from memberships so membership roles stay focused.
- Add durable ban storage separate from memberships because bans survive membership deletion.
- Add append-only moderation audit events for role changes, mute/unmute, timeout/remove timeout, timeout expiry, kick, ban, unban, moderator message delete, and any ban cleanup deletes.
- Author deleting their own message is not a moderation audit event.
- Audit events should preserve actor, target user, workspace, event type, reason when applicable, message or channel context when relevant, and metadata such as timeout duration or cleanup window.
- The audit log is owner-only. Admins can perform moderation actions but cannot view audit history.
- Moderation actions should not create channel system messages.
- Add a simple owner-only audit log screen in the existing authenticated browser pipeline and authenticated LiveView session because audit access depends on `current_scope`, workspace membership, and owner authorization.
- The audit log should show newest events first with event type, actor, target, reason when present, timestamp, and relevant message/channel context.
- Member sidebar grouping should show online Owner, Admins, and Members sections, plus one combined Offline section.
- Offline users should not be visibly role-grouped for regular users.
- Regular members should not see other users’ mute or timeout state.
- The affected user should see their own active mute or timeout state through disabled composer/actions.
- Owners and admins should see active moderation state where it is needed to choose moderation actions.
- Moderation actions should be available from member rows and chat message author/message context menus.
- Chat message context menus for moderators should combine message actions and user moderation actions.
- Kick and ban open confirmation flows because they remove access.
- Mute applies immediately.
- Timeout applies immediately after choosing a preset.
- Message deletion applies immediately with no confirmation and no undo.
- Message deletion is a soft delete and should render a placeholder to viewers.
- Moderator message deletion is audited.
- Own-message deletion is not moderation-audited.
- Deleting a message removes/deletes reactions for that message and blocks future reactions on it.
- Kicked and banned users with open LiveViews should be redirected promptly when possible. Context authorization remains the security boundary.
- Mute, timeout, kick, ban, unban, role changes, and message deletion should broadcast enough workspace/channel state for connected UIs to refresh.
- Channel read/unread fanout should eventually use accessible recipients when private or role-restricted channels exist. For this slice, all channels remain workspace-visible.

## Testing Decisions

- Tests should prove behavior through public context APIs first and LiveView interactions second.
- Add context tests for role validation and migration/backfill behavior.
- Add context tests proving owner/admin/member capability boundaries for workspace rename/delete, channel create/rename/delete, invite creation, role changes, and audit access.
- Add context tests proving admins cannot moderate owners and cannot kick or ban other admins.
- Add context tests proving admins can mute, timeout, and delete messages for admins and members.
- Add context tests proving owners can moderate admins and members.
- Add context tests proving muted and timed-out users cannot send messages, react, type, upload later, or join simulated voice later through public APIs.
- Add context tests proving muted or timed-out admins retain admin capability checks.
- Add tests for mutes with optional reasons and durable active state.
- Add tests for timeout presets, timeout expiry, manual timeout removal, and coexistence with mute.
- Add workspace runtime tests for scheduling existing timeouts on start, scheduling new timeouts, replacing/canceling timers, recording timeout expiry once, and broadcasting state changes.
- Use `Process.monitor/1`, `assert_receive`, and `_ = :sys.get_state/1` where process lifecycle synchronization is needed.
- Avoid `Process.sleep/1` in timeout scheduler tests.
- Add tests for kick requiring a reason, deleting membership, clearing active moderation state, clearing read/unread state, preserving messages, and allowing invite rejoin.
- Add tests for ban requiring a reason, deleting membership, clearing active moderation state, creating a ban record, blocking invite preview/accept, and preserving or cleaning messages according to the chosen cleanup window.
- Add tests proving all-message ban cleanup is owner-only.
- Add tests proving unban removes the ban but does not restore membership or previous role.
- Add tests for moderator message deletion soft-deleting the message, deleting reactions, broadcasting placeholder updates, and creating audit events.
- Add tests for own-message deletion soft-deleting the message, deleting reactions, broadcasting placeholder updates, and not creating moderation audit events.
- Add LiveView tests for member sidebar grouping by online role sections and combined offline section.
- Add LiveView tests proving regular members cannot see other users’ mute/timeout state.
- Add LiveView tests proving affected users see disabled participation controls when muted or timed out.
- Add LiveView tests for member-list context menu action availability by actor/target pair.
- Add LiveView tests for chat message context menu action availability by actor/target pair.
- Add LiveView tests proving kick and ban confirmation flows require reasons.
- Add LiveView tests proving mute and timeout apply immediately.
- Add LiveView tests proving kicked or banned connected users are redirected.
- Add LiveView tests proving owner-only audit log access and member/admin rejection.
- Add LiveView tests proving audit log renders meaningful event rows without exposing audit history to admins or members.
- Follow existing LiveView test patterns that use stable DOM IDs, `element/2`, `has_element?/2`, forms, and rendered outcomes rather than raw HTML assertions.
- Run focused context/runtime/LiveView tests first, then `mix precommit`.

## Out of Scope

- Arbitrary per-user permission overrides.
- Ownership transfer.
- Ban-by-email or ban-by-username for users who are not current members.
- Admin access to the audit log.
- Channel-specific mutes, timeouts, bans, or permissions.
- Private channels or channel-specific read/send/manage overrides.
- Soft-delete or archive semantics for channels.
- Message restore or undo.
- Required reasons for mute, timeout, or message deletion.
- Channel system messages announcing moderation actions.
- Ban cleanup options beyond the fixed windows.
- Upload implementation.
- Real audio or full voice implementation.
- Voice-specific permission splitting such as listen versus speak.
- A full moderation analytics dashboard.
- Background job infrastructure beyond the existing workspace runtime scheduling approach.

## Further Notes

This PRD intentionally treats permissions as the next foundation slice before
uploads, voice simulation, and private or restricted channels. The storage and
capability boundaries should be designed so future custom permission grants can
be added by the owner later without rewriting the first role-based system.

The most important deep module boundary is a small permission/moderation surface
inside the application context. LiveViews should ask whether a user can perform
an action and then call a public workflow to perform it. The workflow should own
authorization, persistence, audit events, PubSub broadcasts, and cleanup.

The audit log is deliberately owner-only even though admins can perform
moderation actions. Admins should receive immediate action feedback, but the
durable moderation history belongs to the owner in this design.
