# Project Structure

This project should stay organized around a clear split between the application
core and the web interface.

The core lives in `lib/discord_clone`. It owns data, business rules, OTP
processes, PubSub orchestration, and Ecto queries.

The interface lives in `lib/discord_clone_web`. It owns routing, LiveViews,
controllers, components, forms, and rendering.

## Target Layout

```text
lib/
  discord_clone/
    application.ex
    repo.ex

    accounts.ex
    accounts/
      user.ex
      user_token.ex
      user_notifier.ex

    workspaces.ex
    workspaces/
      workspace.ex
      workspace_membership.ex
      workspace_invite.ex
      channel.ex

    chat.ex
    chat/
      message.ex
      channel_server.ex
      channel_supervisor.ex
      channel_registry.ex

  discord_clone_web/
    router.ex
    endpoint.ex
    telemetry.ex

    live/
      workspace_live/
        index.ex
        show.ex
        form.ex
      channel_live/
        show.ex
      invite_live/
        show.ex

    components/
      layouts.ex
      core_components.ex
```

## Boundary Rules

Use the public context modules as the main entry points:

- `DiscordClone.Accounts`
- `DiscordClone.Workspaces`
- `DiscordClone.Chat`

LiveViews should call public context functions instead of directly calling
`Repo`, `DynamicSupervisor`, or `Phoenix.PubSub`.

Examples:

```elixir
DiscordClone.Workspaces.create_workspace(...)
DiscordClone.Workspaces.accept_invite(...)
DiscordClone.Chat.send_message(...)
DiscordClone.Chat.join_channel(...)
DiscordClone.Chat.list_recent_messages(...)
```

The core may depend on Phoenix infrastructure only where it is part of the
application runtime, such as PubSub. Domain schemas and query logic should stay
free of web rendering concerns.

## Context Responsibilities

### Accounts

Owns users and authentication-related data.

- users
- user tokens
- user notification helpers

### Workspaces

Owns workspace structure and access rules.

- workspaces
- workspace memberships
- workspace invites
- channels
- workspace access checks
- default channel management

### Chat

Owns message history and live channel behavior.

- messages
- sending messages
- message pagination
- channel GenServers
- channel process supervision
- PubSub broadcasting for chat events

### Web

Owns how users interact with the system.

- routes
- LiveViews
- forms
- page state
- rendering
- component composition

Web modules should stay thin. They should translate user actions into calls to
the core contexts, then render the result.

## Optional Future Enforcement

Saša Jurić's `boundary` library can enforce these dependency rules later, once
the project has enough modules for that to be useful.

For now, keep the rules manually:

- Core modules do not call web modules.
- Web modules call public context APIs.
- Schema modules do not own cross-context workflows.
- OTP internals are hidden behind `DiscordClone.Chat`.
