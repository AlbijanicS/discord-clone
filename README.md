# DiscordClone

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## UUID database baseline

All persisted entities use UUID identifiers. The UUID refactor replaced the old
integer migration history with one fresh baseline and is intentionally
destructive: there is no integer-ID upgrade, compatibility, or data-backfill
path.

After pulling this baseline, discard and rebuild existing local databases:

```sh
mix ecto.reset
MIX_ENV=test mix ecto.reset
```

Both commands delete the data in their target database before recreating the
UUID-native schema.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
