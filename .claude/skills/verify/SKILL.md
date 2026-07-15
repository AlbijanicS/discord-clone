---
name: verify
description: Runtime-verify a change by driving the running Phoenix app in a real browser with Playwright (multi-user presence flows included).
---

# Verifying changes in the running app

LiveViewTest does NOT faithfully simulate client-side stream patching
(morphdom, `phx-update="stream"` containers across remounts). Bugs in the
members sidebar / stream ordering only reproduce in a real browser —
always verify LiveView DOM behavior with Playwright, not just tests.

## Recipe that works

1. **Seed users** (dev DB, never touch existing accounts like `stele`/`mare`):
   `mix run seed.exs` — create `verify_*@example.com` users via
   `Accounts.register_user/1`, set `confirmed_at` with a changeset, then
   `Accounts.update_user_password(user, %{password: "hello world!"})`.
   Create a workspace with `Workspaces.create_workspace(scope, ...)` and add
   members by inserting `WorkspaceMembership` changesets directly.
   Print `workspace.id` / `workspace.default_channel_id` for the browser script.

2. **Run the server**: `mix phx.server` in background (default port 4000; check
   `lsof -i :4000` first). Wait for `curl http://localhost:4000/users/log-in` → 200.
   The code reloader recompiles on request — server log shows
   `Live reload: <file>` + `Compiling` when a change is picked up.

3. **Drive with Playwright** (`npx playwright` is installed globally with
   chromium; `npm install playwright` in scratchpad, `node script.mjs`):
   - Login gotchas: on `/users/log-in`, **wait for `.phx-connected` before
     filling** (LiveView connect resets inputs — flaky otherwise), use the
     `#login_form_password` form, click the "Log in and stay logged in"
     button (no `type=submit` selector), then
     `page.waitForURL(url => !url.pathname.includes('log-in'))`.
   - Viewport ≥ 1280px wide or the members sidebar is hidden (`xl:flex`).
   - Multi-user presence: one `browser.newContext()` per user; a user is
     "online" while their context has the channel page open; `ctx.close()`
     takes them offline (allow ~2-3s for the leave to propagate).

4. **Probe channel switches**, not just mounts: click `#channel-<id> a` links.
   Live-navigate remounts re-stream into a DOM container the client preserves,
   which is where stale stream items appear.

5. **Clean up**: TaskStop the server, `mix run cleanup.exs` deleting
   workspaces owned by and users matching `verify_%@example.com`.
