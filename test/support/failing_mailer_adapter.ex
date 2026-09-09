defmodule DiscordClone.FailingMailerAdapter do
  use Swoosh.Adapter

  def deliver(email, config) do
    send(
      Keyword.fetch!(config, :test_pid),
      {:failed_delivery, email, DiscordClone.Repo.in_transaction?()}
    )

    {:error, {503, %{body: String.duplicate("sensitive-provider-response", 1_000)}}}
  end
end
