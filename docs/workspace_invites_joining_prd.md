# Workspace Invites And Joining PRD

## Problem Statement

The Discord clone now has an authenticated workspace shell where users can
create workspaces, enter landing channels, manage channels, rename workspaces,
and leave or delete workspaces. The next blocker is that a second user cannot
join an existing workspace through the product.

Without invites, the app can only model single-user workspaces or memberships
created directly in tests. That blocks the natural path toward persisted chat,
PubSub, and live messaging, because those later phases need multiple workspace
members who can enter the same channels and see the same durable state.

The immediate problem is to add the smallest complete invite flow: an allowed
workspace member creates an invite link, another logged-in user previews and
accepts that link, the system creates a workspace membership, and the joined
user lands in the workspace landing channel.

## Solution

Add a workspace-level invite creation and acceptance workflow.

Invite creation lives inside the existing authenticated workspace shell. A user
who is allowed by the workspace invite policy sees an icon-only invite action in
the selected workspace header. Clicking it navigates to a workspace-level invite
screen at `/workspaces/:workspace_id/invites/new`, keeping the workspace and
channel sidebars visible while replacing the main channel area with an invite
creation view. The invite screen starts empty and only creates a new invite when
the user explicitly presses a form-backed "Create invite link" button.

Invite acceptance lives in controller routes. A logged-in user opens an invite
link, sees a standalone centered confirmation page with minimal workspace and
inviter information, clicks an accept button, and is redirected to the
workspace landing channel. Anonymous visitors are redirected to login by the
authenticated browser pipeline, and the existing return-to behavior should bring
them back to the invite link after login.

The first UI creates fresh 30-minute invite links with unlimited uses until
expiration. The core workflow should also support caller-provided expiration and
maximum usage through a controlled context API so future UI can expose those
settings without redesigning the domain boundary.

## User Stories

1. As a workspace owner, I want to create an invite link from the workspace shell, so that I can bring another user into my workspace.
2. As an allowed workspace member, I want the invite action near the workspace name, so that inviting people feels like a workspace-level action.
3. As a workspace member, I want invite creation to open inside the existing shell, so that the product feels like a desktop chat app instead of a separate admin page.
4. As a workspace member, I want the invite screen to keep the workspace and channel sidebars visible, so that I can navigate back by clicking a workspace or channel.
5. As a workspace member, I want the invite screen to be workspace-level, so that no channel appears selected for a workflow that grants workspace membership.
6. As a workspace member, I want invite creation to require an explicit button press, so that visiting or refreshing the invite screen does not create links accidentally.
7. As a workspace member, I want each explicit create action to generate a fresh invite link, so that future expiration and max-use settings remain simple.
8. As a workspace member, I want first-slice invite links to expire after 30 minutes, so that stale links do not stay useful forever.
9. As a workspace member, I want first-slice invite links to allow unlimited joins until expiration, so that I can share one link with a small group.
10. As a workspace member, I want to see the absolute invite URL after creation, so that I can paste it outside the app.
11. As a workspace member, I want a copy-to-clipboard button for the invite URL, so that sharing the link is quick.
12. As a workspace member, I want copied feedback after pressing the copy button, so that I know the link was copied.
13. As a workspace member, I want the invite URL to remain selectable, so that I can manually copy it if browser clipboard access fails.
14. As a workspace owner, I want invite creation to follow the workspace invite policy, so that invite permissions are not hard-coded only in the UI.
15. As a non-owner workspace member in an owner-only workspace, I should not see the invite button, so that unavailable actions are not advertised.
16. As a non-owner workspace member in an owner-only workspace, I should be redirected back into the workspace if I manually open the invite creation URL, so that permission failures recover cleanly.
17. As a logged-in non-member, I should not be able to create an invite for a workspace, so that private workspace boundaries are preserved.
18. As an anonymous visitor, I should be redirected to login before previewing or accepting an invite, so that membership changes always attach to an authenticated user.
19. As an anonymous visitor, I want login to return me to the invite link when supported by the existing auth flow, so that accepting an invite is not a dead end.
20. As an invited logged-in user, I want to preview an invite before accepting it, so that joining a workspace is an intentional action.
21. As an invited logged-in user, I want the preview page to show the workspace name, so that I know what I am joining.
22. As an invited logged-in user, I want the preview page to show the inviter when available, so that I understand where the invite came from.
23. As an invited logged-in user, I want the preview page to show which account I am accepting as, so that I do not join with the wrong identity.
24. As an invited logged-in user, I want the preview page to avoid showing private channels or member lists, so that private workspace data remains protected before membership.
25. As an invited logged-in user, I want the accept action to create my workspace membership, so that I can enter the workspace.
26. As an invited logged-in user, I want to land in the workspace landing channel after accepting, so that I can immediately continue into the chat surface.
27. As an existing workspace member, I want opening an invite link to navigate me to the workspace, so that repeated invite clicks are harmless.
28. As an existing workspace member, I do not want accepting an invite to consume invite usage, so that limited invites are reserved for new joins.
29. As a workspace owner, I want invite usage to count new memberships only, so that future max-use limits mean "new people who joined."
30. As a developer, I want invite preview to avoid mutating state, so that GET requests remain safe.
31. As a developer, I want invite acceptance to revalidate the invite transactionally, so that stale preview pages cannot bypass expiration, revocation, or usage limits.
32. As a developer, I want invite acceptance to lock the invite row while checking and incrementing usage, so that concurrent accepts respect maximum usage.
33. As a developer, I want distinct domain outcomes for invalid, revoked, expired, and fully-used invites, so that UI and tests can handle each case clearly.
34. As an invited user, I want invalid invite links to show a clear failure state, so that I know the link cannot be used.
35. As an invited user, I want revoked invite links to show a clear failure state, so that I know the link is no longer active.
36. As an invited user, I want expired invite links to show a clear failure state, so that I know I need a new invite.
37. As an invited user, I want fully-used invite links to show a clear failure state, so that I know the invite has no remaining uses.
38. As a developer, I want invite codes to be random URL-safe case-sensitive tokens, so that links are hard to guess and easy to place in URLs.
39. As a developer, I want invite creation to ignore caller-provided code, creator, workspace, usage count, and revoked state, so that client params cannot spoof server-owned values.
40. As a developer, I want invite creation to accept controlled expiration and maximum usage attrs, so that future UI can expose those settings without changing the core workflow.
41. As a developer, I want the workspace create button to appear everywhere the shell appears, so that shell controls stay consistent across workspace, channel, and invite screens.

## Implementation Decisions

- Build this as the Phase 4 "Invites And Joining" vertical slice.
- The first slice is the complete create-link, preview-link, accept-link,
  create-membership, and land-in-channel workflow.
- The durable invite schema and migration already exist and should be reused.
- No schema changes are required for the first slice.
- Invite creation belongs to the public Workspaces context, because invites are
  workspace structure and access behavior.
- Add a public invite changeset helper for form usage. It should return an Ecto
  changeset and support future expiration and max-use inputs, even though the
  first UI renders no fields.
- Add a public invite creation workflow that takes the current scope, an
  explicit workspace identifier, and controlled invite attrs.
- Invite creation requires an authenticated scope containing a user.
- Invite creation first resolves the workspace through membership-scoped access
  checks.
- Invite creation then enforces workspace invite policy.
- Workspace invite policy means `owner_only` allows only the workspace owner to
  create invites, while `members_can_invite` allows any workspace member to
  create invites.
- New workspaces currently use `owner_only`, so the first visible behavior is
  owner-only invite creation.
- The invite button should only render for users who are allowed by the
  workspace invite policy.
- The context must still enforce invite policy for direct URL visits and forged
  events.
- Direct visits to the invite creation screen by workspace members without
  invite permission should redirect to workspace entry with an error flash.
- Direct visits by non-members should redirect to the workspace index with the
  existing generic access failure behavior.
- Each explicit invite creation creates a fresh invite. It should not reuse a
  previous active invite.
- First-slice default invite expiration is 30 minutes from creation.
- First-slice default maximum usage is nil.
- `max_uses: nil` means unlimited new memberships until expiration or
  revocation.
- Invite codes are case-sensitive random URL-safe tokens.
- Invite codes should be 32 characters, produced from strong random bytes.
- Invite creation should always generate code server-side.
- Invite creation should always set the creator from `current_scope.user`.
- Invite creation should always use the explicit workspace identifier passed to
  the context function.
- Invite creation should always start `uses_count` at zero.
- Invite creation should always start `revoked_at` as nil.
- Caller-provided code, workspace identifier, creator identifier, usage count,
  and revoked state must be ignored.
- Caller-provided `expires_at` and `max_uses` may be accepted through the
  controlled attrs path for tests and future UI, with safe defaults when absent.
- Use `DateTime.utc_now(:second)` directly for this slice rather than adding a
  clock abstraction.
- Add a public invite preview workflow in the Workspaces context.
- Invite preview validates that an invite exists and is usable for preview.
- Invite preview should not create membership or increment usage.
- Invite preview should return enough minimal data to render workspace name,
  inviter username when available, expiration status, and current accepting
  user.
- Invite preview must not return private workspace channel lists, member lists,
  or owner email-like details beyond the current safe display fields.
- Add a public invite acceptance workflow in the Workspaces context.
- Invite acceptance requires an authenticated scope containing a user.
- Invite acceptance revalidates the invite inside the accept operation.
- Invite acceptance should reject missing, revoked, expired, and fully-used
  invites.
- Invite acceptance should lock the invite row during validation and usage
  update so concurrent accepts respect max-use limits.
- Invite acceptance creates a workspace membership for non-members.
- New invite-created memberships always use the `member` workspace role.
- Invite acceptance increments `uses_count` only when a new workspace
  membership is created.
- Existing workspace members who accept an invite should be treated as
  navigation-only.
- Existing workspace members should not create another membership.
- Existing workspace members should not increment `uses_count`.
- Existing workspace members, including owners, should still be redirected to
  the workspace landing channel after accepting.
- Invite acceptance should return enough landing data for the web layer to
  redirect to the workspace landing channel.
- Invite acceptance should resolve the workspace landing channel through the
  same scoped workspace entry rules used elsewhere in the app.
- Invite creation UI should be a LiveView route inside the existing
  authenticated LiveView session.
- The invite creation route should be `/workspaces/:workspace_id/invites/new`.
- The invite creation route belongs in the existing authenticated browser scope
  and existing authenticated LiveView session because it requires a logged-in
  user and current scope.
- The invite creation screen should render the existing workspace shell.
- The invite creation screen should keep the workspace sidebar and channel
  sidebar visible.
- The invite creation screen should be workspace-level and have no selected
  channel.
- The selected workspace header should include an icon-only invite button next
  to the existing workspace action menu.
- The invite button should use the existing icon component with a suitable
  person-plus icon name if available.
- The invite button should include an accessible label.
- The invite screen should use a form-backed submit action, even before custom
  fields exist.
- Creating an invite from the invite screen should stay on the invite screen and
  display the generated link.
- Creating another invite from the same screen should create a fresh invite and
  replace the displayed link.
- The generated invite link displayed in the UI should be an absolute URL.
- The Workspaces context should return invite/domain data, not web URLs.
- The web layer should build the absolute invite URL.
- The invite screen should include a copy-to-clipboard control in the existing
  app JavaScript bundle or LiveView JavaScript commands.
- No inline template scripts should be added.
- Invite acceptance should be handled by controller routes.
- The invite preview route should be a GET route for `/invites/:code`.
- The invite accept route should be a POST route such as
  `/invites/:code/accept`.
- Both invite acceptance routes belong in an authenticated browser scope using
  the `:require_authenticated_user` plug.
- The controller route choice is intentional because the existing authenticated
  plug stores GET return paths for unauthenticated visitors.
- The invite preview and accept pages should use the application layout with
  current scope, but should not render the workspace shell.
- The invite preview page should be a standalone centered page.
- The invite preview page should show a failure state without an accept button
  for invalid, revoked, expired, or fully-used invites.
- After successful accept, redirect to the workspace landing channel.
- After already-member accept, redirect to the workspace landing channel with an
  informational flash.
- The app shell should be updated so the existing create-workspace plus button
  appears anywhere the shell is rendered, including workspace entry, channel
  show, and invite creation screens.
- The shell consistency fix is a small addon to this slice and should not turn
  into a broader shell refactor unless duplication becomes clearly painful.
- Keep web modules thin. LiveViews and controllers translate user actions into
  Workspaces context calls and render outcomes.
- A potential deep module opportunity is the Workspaces invite workflow itself:
  a compact public interface should hide policy checks, token creation,
  expiration validation, max-use validation, membership creation, usage updates,
  and landing-channel resolution behind a small set of testable context
  functions.

## Testing Decisions

- Test public behavior through Workspaces context functions rather than testing
  private helpers.
- Add focused Workspaces context tests for invite creation.
- Invite creation tests should cover authenticated owner success, invite policy
  enforcement, `members_can_invite` behavior when that policy is present,
  unauthenticated scopes, non-members, direct spoofed attrs being ignored,
  generated code shape, default 30-minute expiration, default nil max uses, and
  controlled `expires_at` / `max_uses` attrs.
- Invite creation tests should prove each explicit create call creates a new
  invite.
- Add focused Workspaces context tests for invite preview.
- Invite preview tests should cover valid preview, not found, revoked, expired,
  fully-used, and privacy-safe returned data.
- Add focused Workspaces context tests for invite acceptance.
- Invite acceptance tests should cover new member creation, membership role,
  landing-channel return, usage increment only for new membership, existing
  member navigation-only behavior, revoked rejection, expired rejection,
  fully-used rejection, unauthenticated rejection, and missing invite rejection.
- Invite acceptance tests should verify duplicate membership is handled cleanly.
- Invite acceptance tests should cover max-use semantics, including
  `max_uses: nil` as unlimited and integer max uses as full when
  `uses_count >= max_uses`.
- Concurrency-sensitive behavior should be covered at the context level if it
  can be expressed reliably. At minimum, the context implementation should use
  row locking for the accept transaction and tests should cover the max-use
  boundary.
- Add controller tests for invite preview and accept routes.
- Controller tests should cover anonymous GET redirecting to login and storing
  return-to through the existing authenticated plug.
- Controller tests should cover valid logged-in preview rendering the standalone
  confirmation page.
- Controller tests should cover invalid/revoked/expired/full preview failure
  states without an accept control.
- Controller tests should cover successful POST accept redirecting to the
  workspace landing channel.
- Controller tests should cover already-member POST accept redirecting to the
  workspace landing channel with an informational flash.
- Add LiveView tests for the invite creation screen.
- LiveView tests should use stable DOM IDs, `element/2`, `has_element?/2`, and
  form helpers instead of asserting raw HTML.
- LiveView tests should cover the invite button appearing for allowed users in
  the selected workspace header.
- LiveView tests should cover the invite button being hidden for users who are
  not allowed by invite policy.
- LiveView tests should cover direct unauthorized invite screen access
  redirecting to workspace entry with an error flash.
- LiveView tests should cover the invite creation screen rendering the shell,
  selected workspace, channel list, no selected channel, and invite form.
- LiveView tests should cover submitting the invite form creates and displays an
  absolute invite URL.
- LiveView tests should cover submitting the invite form twice shows a new link.
- LiveView tests should cover the copy control being present; browser clipboard
  behavior can be verified with an integration/browser pass if needed.
- Add LiveView tests for the shell consistency fix so the create-workspace plus
  appears while inside selected workspace/channel/invite shell states.
- Existing Workspaces context tests are the main prior art for public domain
  behavior.
- Existing workspace LiveView tests are the main prior art for shell rendering,
  route authorization, stable DOM IDs, streams, and form interactions.
- Existing user session and user auth tests are the main prior art for
  authenticated controller redirects and return-to behavior.
- Run focused Workspaces tests first.
- Run focused controller and LiveView tests next.
- Run the project precommit alias when implementation is complete.

## Out of Scope

- Invite management list.
- Revoking invites from the UI.
- Editing invite expiration from the UI.
- Editing invite max-use count from the UI.
- Emailing invites.
- Anonymous invite preview before login.
- Accepting invites during registration without revisiting the link.
- Per-channel invites.
- Invite-created role selection.
- Workspace role management beyond the current `owner` and `member` roles.
- Workspace invite policy management UI.
- Workspace member management UI.
- Showing member lists on the invite preview page.
- Showing channel lists on the invite preview page before membership.
- Persisted message sending.
- Message history queries.
- PubSub message delivery.
- Channel GenServers.
- Presence and typing indicators.
- Broader app shell refactors beyond restoring the workspace create action and
  adding the invite screen state.
- Publishing this PRD to an issue tracker.

## Further Notes

This PRD comes from a `grill-me` session for the Phase 4 invite/join planning
work. The user capped the grill at 41 questions and explicitly chose the
controller-based invite acceptance path, the shell-based invite creation path,
fresh 30-minute invite links, a standalone preview page, and a workspace-level
invite creation screen with no selected channel.

The route placement decision is important:

- Invite creation belongs in the existing authenticated LiveView session under
  the authenticated browser scope because it renders the workspace shell and
  requires `current_scope`.
- Invite preview and accept belong in authenticated controller routes because
  accepting creates membership for the logged-in user, and the existing
  authenticated controller plug already stores return-to paths for unauthenticated
  GET requests.

Issue tracker publishing is blocked because this repository still does not
define the tracker configuration or triage label vocabulary expected by the
local `to-prd` skill. Existing PRDs in this repository use the same docs-first
fallback and note that tracker setup has not been completed.
