defmodule DiscordClone.RuntimeConfigurationTest do
  use ExUnit.Case, async: false

  @runtime_environment %{
    "DATABASE_URL" => "ecto://placeholder:placeholder@localhost/placeholder",
    "PHX_HOST" => "alpha.example.test",
    "PORT" => "4100",
    "SECRET_KEY_BASE" => String.duplicate("placeholder", 8),
    "VOICE_ICE_MODE" => "standard"
  }

  setup do
    previous_values =
      Map.new(@runtime_environment, fn {key, _value} -> {key, System.get_env(key)} end)

    Enum.each(@runtime_environment, fn {key, value} -> System.put_env(key, value) end)

    on_exit(fn ->
      Enum.each(previous_values, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)
  end

  test "production runtime binds Phoenix to IPv4 loopback behind the public HTTPS endpoint" do
    runtime_config = Config.Reader.read!("config/runtime.exs", env: :prod)
    endpoint_config = runtime_config[:discord_clone][DiscordCloneWeb.Endpoint]

    assert endpoint_config[:http][:ip] == {127, 0, 0, 1}
    assert endpoint_config[:http][:port] == 4100
    assert endpoint_config[:url] == [host: "alpha.example.test", port: 443, scheme: "https"]

    assert runtime_config[:discord_clone][DiscordClone.Voice.ICEConfigurationResolver] ==
             [mode: :standard]
  end

  test "production rejects a missing explicit hosted ICE mode" do
    System.delete_env("VOICE_ICE_MODE")

    assert_raise RuntimeError, ~r/VOICE_ICE_MODE must be standard or turn_only/, fn ->
      Config.Reader.read!("config/runtime.exs", env: :prod)
    end
  end

  test "non-production runtime does not replace the environment-specific listener binding" do
    runtime_config = Config.Reader.read!("config/runtime.exs", env: :test)
    endpoint_config = runtime_config[:discord_clone][DiscordCloneWeb.Endpoint]

    assert endpoint_config[:http] == [port: 4100]
  end

  test "production keeps proxy-aware SSL rewriting" do
    production_config = Config.Reader.read!("config/prod.exs", env: :prod)
    endpoint_config = production_config[:discord_clone][DiscordCloneWeb.Endpoint]

    assert endpoint_config[:force_ssl][:rewrite_on] == [:x_forwarded_proto]
  end
end
