defmodule DiscordClone.Voice.ICEConfigurationResolver do
  @moduledoc """
  Resolves one provider-neutral ICE bundle for each Voice admission attempt.

  Development and tests remain deterministic when no configuration is present:
  the resolver uses disabled mode and never invokes a hosted provider.
  """

  alias DiscordClone.Voice.{DeploymentCapacity, ServerICEProjection, SessionICEBundle}

  @application :discord_clone
  @authorization_keys [:credential, :expires_at, :urls, :username]
  @default_provider_timeout_ms 3_000
  @default_minimum_credential_lifetime_seconds 60
  @maximum_provider_timeout_ms 3_000
  @hosted_configuration_keys [
    :external_ipv4,
    :internal_ipv4,
    :max_active_sessions,
    :minimum_credential_lifetime_seconds,
    :mode,
    :provider,
    :provider_options,
    :provider_secret,
    :provider_timeout_ms,
    :stun_urls,
    :udp_port_range
  ]

  @doc """
  Validates only static Voice ICE configuration.

  This startup-safe check deliberately never invokes the hosted provider.
  """
  @spec validate_static_configuration() :: :ok | {:error, :invalid_configuration}
  def validate_static_configuration do
    configured_options()
    |> validate_static_configuration()
  end

  @spec resolve() ::
          {:ok, SessionICEBundle.t()}
          | {:error, :invalid_configuration | :invalid_provider_response | :provider_unavailable}
  def resolve do
    options = configured_options()

    with :ok <- validate_static_configuration(options) do
      resolve_config(options)
    end
  end

  defp validate_static_configuration(options) when is_list(options) do
    if Keyword.keyword?(options) and unique_configuration_keys?(options) do
      case Keyword.fetch(options, :mode) do
        {:ok, :disabled} ->
          :ok

        {:ok, mode} when mode in [:standard, :turn_only] ->
          validate_hosted_configuration(options)

        :error ->
          {:error, :invalid_configuration}

        {:ok, _unsupported_mode} ->
          {:error, :invalid_configuration}
      end
    else
      {:error, :invalid_configuration}
    end
  end

  defp validate_static_configuration(_options), do: {:error, :invalid_configuration}

  defp resolve_config(options) when is_list(options) do
    case Keyword.fetch(options, :mode) do
      {:ok, :disabled} -> disabled_bundle()
      {:ok, mode} when mode in [:standard, :turn_only] -> hosted_bundle(mode, options)
      _unsupported_mode -> {:error, :invalid_configuration}
    end
  end

  defp resolve_config(_options), do: {:error, :invalid_configuration}

  defp disabled_bundle do
    {:ok,
     %SessionICEBundle{
       mode: :disabled,
       browser_projection: %{ice_mode: "disabled", ice_servers: [], ice_transport_policy: "all"},
       server_projection: ServerICEProjection.disabled(),
       expires_at: nil
     }}
  end

  defp hosted_bundle(mode, options) do
    stun_urls = Keyword.fetch!(options, :stun_urls)
    provider = Keyword.fetch!(options, :provider)
    provider_options = Keyword.get(options, :provider_options, [])
    provider_secret = Keyword.fetch!(options, :provider_secret)

    provider_timeout_ms =
      Keyword.get(options, :provider_timeout_ms) || @default_provider_timeout_ms

    minimum_lifetime_seconds =
      Keyword.get(options, :minimum_credential_lifetime_seconds) ||
        @default_minimum_credential_lifetime_seconds

    {:ok, media_configuration} = hosted_media_configuration(options)

    with {:ok, authorization} <-
           request_authorization(
             provider,
             Keyword.put(provider_options, :secret, provider_secret),
             provider_timeout_ms
           ),
         {:ok, authorization} <- validate_authorization(authorization, minimum_lifetime_seconds),
         {:ok, server_projection} <-
           server_projection(
             mode,
             stun_urls,
             authorization,
             media_configuration
           ) do
      {:ok,
       %SessionICEBundle{
         mode: mode,
         browser_projection: browser_projection(mode, stun_urls, authorization),
         server_projection: server_projection,
         expires_at: authorization.expires_at
       }}
    end
  end

  defp validate_hosted_configuration(options) do
    with true <- Keyword.keyword?(options),
         true <- Enum.all?(Keyword.keys(options), &(&1 in @hosted_configuration_keys)),
         {:ok, _stun_urls} <-
           validate_stun_urls(Keyword.get(options, :mode), Keyword.get(options, :stun_urls)),
         {:ok, _provider, _provider_options} <- provider_config(options),
         true <- non_blank_string?(Keyword.get(options, :provider_secret)),
         true <- valid_provider_timeout?(Keyword.get(options, :provider_timeout_ms)),
         true <-
           valid_minimum_lifetime?(Keyword.get(options, :minimum_credential_lifetime_seconds)),
         {:ok, _media_configuration} <- hosted_media_configuration(options) do
      :ok
    else
      _invalid_configuration -> {:error, :invalid_configuration}
    end
  end

  defp validate_stun_urls(:standard, urls) when is_list(urls) and urls != [] do
    if Enum.all?(urls, &stun_url?/1),
      do: {:ok, urls},
      else: {:error, :invalid_configuration}
  end

  defp validate_stun_urls(:turn_only, []), do: {:ok, []}
  defp validate_stun_urls(_mode, _urls), do: {:error, :invalid_configuration}

  defp provider_config(options) do
    provider = Keyword.get(options, :provider)
    provider_options = Keyword.get(options, :provider_options, [])

    if is_atom(provider) and Code.ensure_loaded?(provider) and
         function_exported?(provider, :resolve, 1) and
         is_list(provider_options) and Keyword.keyword?(provider_options) and
         not Keyword.has_key?(provider_options, :secret) do
      {:ok, provider, provider_options}
    else
      {:error, :invalid_configuration}
    end
  end

  defp request_authorization(provider, provider_options, timeout_ms) do
    request_ref = make_ref()
    caller = self()

    {provider_pid, monitor_ref} =
      spawn_monitor(fn ->
        send(caller, {request_ref, invoke_provider(provider, provider_options)})
      end)

    receive do
      {^request_ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        normalize_provider_result(result)

      {:DOWN, ^monitor_ref, :process, ^provider_pid, _reason} ->
        {:error, :provider_unavailable}
    after
      timeout_ms ->
        Process.exit(provider_pid, :kill)
        Process.demonitor(monitor_ref, [:flush])
        {:error, :provider_unavailable}
    end
  end

  defp invoke_provider(provider, provider_options) do
    provider.resolve(provider_options)
  rescue
    _provider_error -> {:error, :unavailable}
  catch
    _kind, _provider_error -> {:error, :unavailable}
  end

  defp normalize_provider_result(result) do
    case result do
      {:ok, authorization} -> {:ok, authorization}
      {:error, :invalid_response} -> {:error, :invalid_provider_response}
      {:error, _bounded_or_provider_error} -> {:error, :provider_unavailable}
      _invalid_return -> {:error, :invalid_provider_response}
    end
  end

  defp validate_authorization(%{} = authorization, minimum_lifetime_seconds) do
    with true <- Enum.sort(Map.keys(authorization)) == @authorization_keys,
         urls when is_list(urls) and urls != [] <- authorization.urls,
         true <- Enum.all?(urls, &turn_url?/1),
         true <- non_blank_string?(authorization.username),
         true <- non_blank_string?(authorization.credential),
         %DateTime{} = expires_at <- authorization.expires_at,
         true <- sufficient_lifetime?(expires_at, minimum_lifetime_seconds) do
      {:ok, authorization}
    else
      _invalid_authorization -> {:error, :invalid_provider_response}
    end
  end

  defp validate_authorization(_authorization, _minimum_lifetime_seconds),
    do: {:error, :invalid_provider_response}

  defp server_projection(
         mode,
         stun_urls,
         authorization,
         media_configuration
       ) do
    udp_turn_urls = preferred_server_turn_urls(authorization.urls)

    if udp_turn_urls == [] do
      {:error, :invalid_provider_response}
    else
      ServerICEProjection.new(
        ice_mode: mode,
        ice_servers: server_ice_servers(mode, stun_urls, authorization, udp_turn_urls),
        transport_policy: server_transport_policy(mode),
        host_to_srflx_ip_mapper:
          exact_ipv4_mapper(
            media_configuration.internal_ipv4,
            media_configuration.external_ipv4
          ),
        udp_port_range: media_configuration.udp_port_range
      )
      |> case do
        {:ok, projection} -> {:ok, projection}
        {:error, :invalid_server_ice_projection} -> {:error, :invalid_provider_response}
      end
    end
  end

  defp browser_projection(mode, stun_urls, authorization) do
    %{
      ice_mode: Atom.to_string(mode),
      ice_servers: browser_ice_servers(mode, stun_urls, authorization),
      ice_transport_policy: browser_transport_policy(mode)
    }
  end

  defp browser_ice_servers(:standard, stun_urls, authorization),
    do: [%{urls: stun_urls}, turn_ice_server(authorization, authorization.urls)]

  defp browser_ice_servers(:turn_only, _stun_urls, authorization),
    do: [turn_ice_server(authorization, authorization.urls)]

  defp server_ice_servers(:standard, stun_urls, authorization, udp_turn_urls),
    do: [%{urls: stun_urls}, turn_ice_server(authorization, udp_turn_urls)]

  defp server_ice_servers(:turn_only, _stun_urls, authorization, udp_turn_urls),
    do: [turn_ice_server(authorization, udp_turn_urls)]

  defp turn_ice_server(authorization, urls) do
    %{
      urls: urls,
      username: authorization.username,
      credential: authorization.credential
    }
  end

  defp browser_transport_policy(:standard), do: "all"
  defp browser_transport_policy(:turn_only), do: "relay"

  defp server_transport_policy(:standard), do: :all
  defp server_transport_policy(:turn_only), do: :relay

  defp stun_url?(url) do
    case parse_ice_url(url) do
      {:ok, %{scheme: :stun}} -> true
      _invalid_url -> false
    end
  end

  defp turn_url?(url) do
    case parse_ice_url(url) do
      {:ok, %{scheme: scheme}} when scheme in [:turn, :turns] -> true
      _invalid_url -> false
    end
  end

  defp server_turn_url?(url) do
    case parse_ice_url(url) do
      {:ok, %{scheme: :turn, transport: transport}} when transport in [nil, :udp] -> true
      _unsupported_url -> false
    end
  end

  defp preferred_server_turn_urls(urls) do
    udp_urls = Enum.filter(urls, &server_turn_url?/1)

    case Enum.find(udp_urls, &default_turn_port?/1) || List.first(udp_urls) do
      nil -> []
      url -> [url]
    end
  end

  defp default_turn_port?(url) do
    case parse_ice_url(url) do
      {:ok, %{port: 3478}} -> true
      _other_port -> false
    end
  end

  defp parse_ice_url(url) when is_binary(url) and byte_size(url) > 0,
    do: ExSTUN.URI.parse(url)

  defp parse_ice_url(_url), do: {:error, :invalid_uri}

  defp non_blank_string?(value),
    do: is_binary(value) and value |> String.trim() |> byte_size() > 0

  defp hosted_media_configuration(options) do
    udp_port_range = Keyword.get(options, :udp_port_range)
    max_active_sessions = Keyword.get(options, :max_active_sessions)

    with {:ok, internal_ipv4} <- validate_internal_ipv4(Keyword.get(options, :internal_ipv4)),
         {:ok, external_ipv4} <- validate_external_ipv4(Keyword.get(options, :external_ipv4)),
         true <-
           DeploymentCapacity.valid_configuration?(udp_port_range, max_active_sessions) do
      {:ok,
       %{
         internal_ipv4: internal_ipv4,
         external_ipv4: external_ipv4,
         udp_port_range: udp_port_range
       }}
    else
      _invalid_configuration -> {:error, :invalid_configuration}
    end
  end

  defp validate_internal_ipv4(value) do
    with {:ok, address} <- parse_ipv4(value),
         true <- private_ipv4?(address) do
      {:ok, address}
    else
      _invalid_address -> {:error, :invalid_configuration}
    end
  end

  defp validate_external_ipv4(value) do
    with {:ok, address} <- parse_ipv4(value),
         true <- public_unicast_ipv4?(address) do
      {:ok, address}
    else
      _invalid_address -> {:error, :invalid_configuration}
    end
  end

  defp parse_ipv4(value) when is_binary(value) do
    value
    |> String.to_charlist()
    |> :inet.parse_ipv4_address()
  end

  defp parse_ipv4(_value), do: {:error, :einval}

  defp private_ipv4?({10, _b, _c, _d}), do: true
  defp private_ipv4?({172, b, _c, _d}) when b in 16..31, do: true
  defp private_ipv4?({192, 168, _c, _d}), do: true
  defp private_ipv4?(_address), do: false

  defp public_unicast_ipv4?({first, _b, _c, _d}) when first in [0, 10, 127] or first >= 224,
    do: false

  defp public_unicast_ipv4?({100, b, _c, _d}) when b in 64..127, do: false
  defp public_unicast_ipv4?({169, 254, _c, _d}), do: false
  defp public_unicast_ipv4?({172, b, _c, _d}) when b in 16..31, do: false
  defp public_unicast_ipv4?({192, 0, _c, _d}), do: false
  defp public_unicast_ipv4?({192, 168, _c, _d}), do: false
  defp public_unicast_ipv4?({198, b, _c, _d}) when b in 18..19 or b == 51, do: false
  defp public_unicast_ipv4?({203, 0, 113, _d}), do: false
  defp public_unicast_ipv4?({_first, _b, _c, _d}), do: true

  defp exact_ipv4_mapper(internal_ipv4, external_ipv4) do
    fn
      ^internal_ipv4 -> external_ipv4
      _other_address -> nil
    end
  end

  defp valid_provider_timeout?(nil), do: true

  defp valid_provider_timeout?(timeout_ms),
    do: is_integer(timeout_ms) and timeout_ms in 1..@maximum_provider_timeout_ms

  defp valid_minimum_lifetime?(nil), do: true

  defp valid_minimum_lifetime?(seconds),
    do: is_integer(seconds) and seconds > 0

  defp unique_configuration_keys?(options) do
    keys = Keyword.keys(options)
    Enum.uniq(keys) == keys
  end

  defp configured_options do
    Application.get_env(@application, __MODULE__) || [mode: :disabled]
  end

  defp sufficient_lifetime?(expires_at, minimum_lifetime_seconds) do
    minimum_expiry = DateTime.add(DateTime.utc_now(), minimum_lifetime_seconds, :second)
    DateTime.compare(expires_at, minimum_expiry) in [:eq, :gt]
  end
end
