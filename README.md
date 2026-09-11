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

Local Voice deliberately uses disabled ICE mode: no cloud account, STUN, TURN,
public IP mapping, or certificate is required on `localhost`.

## AWS private-alpha production release

The private-alpha topology is one Ubuntu EC2 VM behind an Elastic IPv4 address.
Caddy accepts HTTPS/WSS on TCP 80/443 and proxies to Phoenix on
`127.0.0.1:4000`. ExWebRTC media uses UDP 50000-50031 directly; Cloudflare
Realtime TURN provides STUN and fresh, short-lived TURN credentials per Voice
admission. Public registration and magic-link login are disabled; provision
confirmed password accounts with the release command below.

Build on the ARM64 VM after syncing the source:

```sh
cd /tmp/discord_clone_build
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
sudo rsync -a --delete _build/prod/rel/discord_clone/ /opt/discord_clone/
sudo chown -R discord-clone:discord-clone /opt/discord_clone
```

Install the tracked service definitions:

```sh
sudo install -o root -g root -m 0644 deploy/discord-clone.service.example \
  /etc/systemd/system/discord-clone.service
sudo sed 's/alpha\.example\.com/voiceechattest.duckdns.org/g' \
  deploy/Caddyfile.example | sudo tee /etc/caddy/Caddyfile >/dev/null
```

`/etc/discord-clone.env` must be owned by `root:discord-clone`, mode `0640`,
and contain unindented `NAME=value` lines for:

```text
PHX_HOST=voiceechattest.duckdns.org
PORT=4000
DATABASE_URL=<production PostgreSQL URL>
SECRET_KEY_BASE=<unique output from mix phx.gen.secret>
POOL_SIZE=5
RELEASE_DISTRIBUTION=none
VOICE_ICE_MODE=standard
VOICE_STUN_URLS=stun:stun.cloudflare.com:3478
VOICE_INTERNAL_IPV4=<EC2 private IPv4>
VOICE_EXTERNAL_IPV4=<Elastic IPv4>
VOICE_TURN_CREDENTIAL_TTL_SECONDS=3600
CLOUDFLARE_TURN_KEY_ID=<Cloudflare TURN key ID>
CLOUDFLARE_TURN_API_TOKEN=<Cloudflare TURN key API token>
PHX_SERVER=true
```

Accounts are provisioned by the operator over SSH using the release command
below. Self-service email changes are not available. No email provider account,
sending domain, or mail API key is required to run production.

`VOICE_STUN_URLS` is required in `standard` mode. In `turn_only` mode it is
ignored and the application supplies only Cloudflare TURN URLs to browsers and
the server.

Never commit or paste that file. The EC2 security group should expose only SSH
from the operator IP, TCP 80/443 publicly, and UDP 50000-50031 publicly. Do not
expose Phoenix 4000, PostgreSQL 5432, EPMD 4369, or Erlang distribution ports.

Run migrations and start the services:

```sh
sudo systemctl daemon-reload
sudo systemd-run --wait --pipe --collect \
  --property=User=discord-clone \
  --property=Group=discord-clone \
  --property=WorkingDirectory=/opt/discord_clone \
  --property=EnvironmentFile=/etc/discord-clone.env \
  /opt/discord_clone/bin/migrate
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl enable --now discord-clone caddy
sudo systemctl --no-pager --full status discord-clone caddy
```

Provision a confirmed test account without placing its password in command
arguments:

```sh
sudo -i
export DISCORD_CLONE_USER_EMAIL='colleague@example.com'
export DISCORD_CLONE_USERNAME='colleague_name'
read -rsp 'Temporary password: ' DISCORD_CLONE_USER_PASSWORD
export DISCORD_CLONE_USER_PASSWORD
systemd-run --wait --pipe --collect \
  --property=User=discord-clone \
  --property=Group=discord-clone \
  --property=WorkingDirectory=/opt/discord_clone \
  --property=EnvironmentFile=/etc/discord-clone.env \
  --setenv=DISCORD_CLONE_USER_EMAIL \
  --setenv=DISCORD_CLONE_USERNAME \
  --setenv=DISCORD_CLONE_USER_PASSWORD \
  /opt/discord_clone/bin/provision-user
unset DISCORD_CLONE_USER_EMAIL DISCORD_CLONE_USERNAME DISCORD_CLONE_USER_PASSWORD
exit
```

Verify `/healthz` and `/readyz` over HTTPS, then test normal Voice on two
different networks. For the relay proof, temporarily set `VOICE_ICE_MODE` to
`turn_only`, restart the service, test two-way audio, then restore `standard`.
Record the result using the acceptance matrix in
[`docs/phase_12_aws_private_alpha_deployment_contract.md`](docs/phase_12_aws_private_alpha_deployment_contract.md).

The one-hour TURN credential lifetime limits how long a credential remains
useful if a client or diagnostic captures it. Keep the Cloudflare TURN key only
in `/etc/discord-clone.env`, and replace the key after any suspected exposure.

### Pause or remove the private alpha

For a reversible pause, stop the public services before stopping the EC2
instance:

```sh
sudo systemctl disable --now discord-clone caddy
sudo systemctl --no-pager --full status discord-clone caddy
```

Then choose **Instance state > Stop instance** in the EC2 console. A stopped
instance does not serve traffic or incur EC2 instance-usage charges, but its EBS
volumes and allocated public IPv4 address can still incur charges. Delete the
Cloudflare TURN key in **Realtime > TURN** as well; stopping Phoenix prevents new
credential generation, while deleting the key removes the long-lived authority
used to issue credentials. Existing short-lived credentials expire within the
configured one-hour TTL.

To resume a stopped instance, start it in EC2, create a new Cloudflare TURN key,
replace `CLOUDFLARE_TURN_KEY_ID` and `CLOUDFLARE_TURN_API_TOKEN` in
`/etc/discord-clone.env`, and run:

```sh
sudo systemctl enable --now caddy discord-clone
sudo systemctl --no-pager --full status caddy discord-clone
```

For the lowest ongoing AWS cost, first export and download a PostgreSQL backup,
then terminate the EC2 instance, verify that every unneeded EBS volume was
deleted, and release the Elastic IP address. Termination and volume deletion are
irreversible; a retained EBS volume or snapshot continues to incur storage
charges. A replacement VM also requires restoring the database and updating DNS
if its public address changes.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
