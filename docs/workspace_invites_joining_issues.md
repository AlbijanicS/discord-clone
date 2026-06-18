# Workspace Invites And Joining Issues

This document breaks `docs/workspace_invites_joining_prd.md` into thin,
independently grabbable vertical slices. The project is using a docs-first
fallback for now, so these are not published to GitHub Issues.

## 1. Owner Creates Invite Link From Workspace Shell

**Type:** AFK

**Blocked by:** None - can start immediately

**User stories covered:** 1-13, 38-40

## What to build

Add the first complete invite creation path for an allowed workspace member.
The invite creation screen lives at `/workspaces/:workspace_id/invites/new`
inside the existing authenticated LiveView session and authenticated browser
scope, because it requires `current_scope` and renders the private workspace
shell.

The screen should keep the workspace and channel sidebars visible, leave no
channel selected, and only create an invite after the user submits the
form-backed create action. Each submit creates a fresh 30-minute invite with
unlimited uses until expiration, displays an absolute invite URL, and provides
a copy control while keeping the URL selectable.

The Workspaces context should expose the public form/change helper and invite
creation workflow. The context should generate the invite code server-side, set
the creator from `current_scope.user`, use the explicit workspace identifier,
start `uses_count` at zero, start `revoked_at` as nil, ignore spoofed
server-owned attrs, and accept controlled `expires_at` / `max_uses` attrs for
tests and future UI.

## Acceptance criteria

- [ ] The invite creation route is placed in the existing authenticated browser
      scope and existing `live_session :require_authenticated_user`.
- [ ] The invite creation screen renders inside the existing workspace shell
      with workspace and channel sidebars visible and no selected channel.
- [ ] Visiting or refreshing the invite creation screen does not create an
      invite.
- [ ] Submitting the invite form creates a fresh invite and displays an
      absolute URL for `/invites/:code`.
- [ ] Submitting the form twice replaces the displayed link with a different
      fresh invite link.
- [ ] First-slice invites default to expiring 30 minutes from creation and
      `max_uses: nil`.
- [ ] Invite codes are 32-character random URL-safe case-sensitive tokens.
- [ ] Caller-provided code, workspace identifier, creator identifier, usage
      count, and revoked state are ignored.
- [ ] Caller-provided `expires_at` and `max_uses` can be accepted through the
      controlled context attrs path.
- [ ] The invite URL remains selectable and the copy control is present without
      inline template scripts.
- [ ] Focused Workspaces context tests and LiveView tests cover the behavior.

## Blocked by

None - can start immediately

## 2. Enforce Workspace Invite Policy End To End

**Type:** AFK

**Blocked by:** 1. Owner Creates Invite Link From Workspace Shell

**User stories covered:** 14-17

## What to build

Make workspace invite permissions consistent across the Workspaces context,
shell UI, and direct route access. `owner_only` allows only the workspace owner
to create invites. `members_can_invite` allows any workspace member to create
invites.

The selected workspace header should show an icon-only invite action only when
the current workspace member is allowed by the workspace invite policy. The
context must still enforce the same rule for forged events and direct URL
visits. Workspace members without invite permission should recover back into
workspace entry with an error flash. Logged-in non-members should recover to
the workspace index with the existing generic access failure behavior.

## Acceptance criteria

- [ ] The Workspaces context enforces `owner_only` and
      `members_can_invite` for invite creation.
- [ ] Owners in `owner_only` workspaces can create invites.
- [ ] Non-owner members in `owner_only` workspaces cannot create invites.
- [ ] Any member in `members_can_invite` workspaces can create invites.
- [ ] Logged-in non-members cannot create invites for private workspaces.
- [ ] The selected workspace header shows the invite action only for users
      allowed by the invite policy.
- [ ] Direct invite-screen visits by disallowed members redirect back into
      workspace entry with an error flash.
- [ ] Direct invite-screen visits by non-members redirect to `/workspaces` with
      the generic access failure behavior.
- [ ] Focused context and LiveView tests cover policy and route recovery.

## Blocked by

- 1. Owner Creates Invite Link From Workspace Shell

## 3. Preview Invite Without Joining

**Type:** AFK

**Blocked by:** 1. Owner Creates Invite Link From Workspace Shell

**User stories covered:** 18-24, 30, 34

## What to build

Add the authenticated invite preview path. The GET route `/invites/:code`
belongs in an authenticated browser scope using the
`:require_authenticated_user` plug, because invite preview requires a logged-in
user and the existing plug can preserve return-to behavior for anonymous GET
requests.

The preview page should be a standalone centered page using the app layout, not
the workspace shell. It should show enough minimal information for an invited
logged-in user to intentionally join: workspace name, inviter username when
available, and the account they are accepting as. It must not reveal private
channels, member lists, or owner email-like details before membership.

The Workspaces context should expose a public preview workflow that validates
the invite for preview, returns privacy-safe render data, and does not create a
membership or increment usage.

## Acceptance criteria

- [ ] GET `/invites/:code` is placed in an authenticated browser scope using
      `:require_authenticated_user`.
- [ ] Anonymous visitors are redirected to login and the existing return-to
      behavior can bring them back to the invite URL.
- [ ] Logged-in users can preview a valid invite before accepting it.
- [ ] The preview page shows workspace name, inviter username when available,
      and the current accepting account.
- [ ] The preview page does not show private channel lists, member lists, or
      owner email-like details.
- [ ] Previewing an invite does not create a workspace membership.
- [ ] Previewing an invite does not increment `uses_count`.
- [ ] Missing invite codes render a clear failure state without an accept
      button.
- [ ] Focused Workspaces context tests and controller tests cover preview
      behavior.

## Blocked by

- 1. Owner Creates Invite Link From Workspace Shell

## 4. Accept Valid Invite And Enter Landing Channel

**Type:** AFK

**Blocked by:** 3. Preview Invite Without Joining

**User stories covered:** 25-26, 31-32

## What to build

Add the authenticated invite accept path. The POST route
`/invites/:code/accept` belongs in an authenticated browser scope using the
`:require_authenticated_user` plug.

The Workspaces context should expose a public acceptance workflow that
revalidates the invite inside the accept operation, locks the invite row during
validation and usage update, creates a `member` workspace membership for
non-members, increments usage for new memberships, resolves the workspace
landing channel through the existing scoped workspace entry rules, and returns
enough landing data for the controller to redirect to the workspace landing
channel.

## Acceptance criteria

- [ ] POST `/invites/:code/accept` is placed in an authenticated browser scope
      using `:require_authenticated_user`.
- [ ] Accepting a valid invite as a logged-in non-member creates a workspace
      membership.
- [ ] Invite-created memberships use the `member` workspace role.
- [ ] Accepting a valid invite increments `uses_count` when a new membership is
      created.
- [ ] Invite acceptance revalidates the invite inside the accept operation.
- [ ] Invite acceptance locks the invite row while checking and incrementing
      usage.
- [ ] Successful accept redirects to the workspace landing channel.
- [ ] Landing-channel resolution uses the same scoped workspace entry rules as
      the rest of the app.
- [ ] Focused Workspaces context tests and controller tests cover successful
      acceptance.

## Blocked by

- 3. Preview Invite Without Joining

## 5. Handle Existing Members And Usage Semantics

**Type:** AFK

**Blocked by:** 4. Accept Valid Invite And Enter Landing Channel

**User stories covered:** 27-29

## What to build

Make invite acceptance harmless for users who already belong to the workspace.
Existing workspace members, including owners, should be treated as a
navigation-only path: accepting the invite should not create another
membership, should not increment `uses_count`, and should redirect to the
workspace landing channel with an informational flash.

This keeps future max-use limits meaningful by counting new people who joined,
not repeated clicks from existing members.

## Acceptance criteria

- [ ] Existing workspace members who accept an invite are redirected to the
      workspace landing channel.
- [ ] Existing workspace members do not create duplicate membership rows.
- [ ] Existing workspace members do not increment `uses_count`.
- [ ] Workspace owners follow the same navigation-only behavior when accepting
      an invite to their own workspace.
- [ ] The controller sets an informational flash for already-member accepts.
- [ ] Duplicate membership handling is covered by context and controller tests.

## Blocked by

- 4. Accept Valid Invite And Enter Landing Channel

## 6. Surface Invalid, Revoked, Expired, And Fully Used Invites

**Type:** AFK

**Blocked by:** 4. Accept Valid Invite And Enter Landing Channel

**User stories covered:** 31, 33-37

## What to build

Add clear domain outcomes and UI states for unusable invites. The Workspaces
context should distinguish invalid, revoked, expired, and fully-used invites so
controllers, templates, and tests can handle each case explicitly.

Preview should show a clear failure state without an accept button. Acceptance
should revalidate inside the transaction so stale preview pages cannot bypass
expiration, revocation, or usage limits. `max_uses: nil` means unlimited new
memberships until expiration or revocation. Integer `max_uses` is full when
`uses_count >= max_uses`.

## Acceptance criteria

- [ ] The Workspaces context returns distinct outcomes for missing, revoked,
      expired, and fully-used invites.
- [ ] Preview pages show clear failure states for invalid, revoked, expired,
      and fully-used invites.
- [ ] Failure preview states do not render an accept control.
- [ ] Accepting revoked, expired, fully-used, or missing invites fails without
      creating membership.
- [ ] Accepting revoked, expired, fully-used, or missing invites fails without
      incrementing `uses_count`.
- [ ] `max_uses: nil` behaves as unlimited until expiration or revocation.
- [ ] Integer `max_uses` behaves as full when `uses_count >= max_uses`.
- [ ] Max-use boundary behavior is covered by focused context tests.

## Blocked by

- 4. Accept Valid Invite And Enter Landing Channel

## 7. Keep Shell Create-Workspace Action Consistent

**Type:** AFK

**Blocked by:** 1. Owner Creates Invite Link From Workspace Shell

**User stories covered:** 41

## What to build

Restore or verify the shell-level create-workspace plus action everywhere the
workspace shell renders, including workspace entry, channel show, and invite
creation screen states. Keep this as a small shell consistency fix and avoid a
broader shell refactor unless duplication becomes clearly painful.

## Acceptance criteria

- [ ] The create-workspace plus action appears on the workspace index shell
      when the inline create form is hidden.
- [ ] The create-workspace plus action appears while viewing workspace entry.
- [ ] The create-workspace plus action appears while viewing a selected
      channel.
- [ ] The create-workspace plus action appears while viewing the invite
      creation screen.
- [ ] Existing workspace creation behavior remains context-backed and uses the
      existing form conventions.
- [ ] LiveView tests cover the shell consistency behavior with stable DOM IDs.

## Blocked by

- 1. Owner Creates Invite Link From Workspace Shell
