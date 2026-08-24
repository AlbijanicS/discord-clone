defmodule DiscordClone.Voice.FakeICEProvider do
  @moduledoc false

  @behaviour DiscordClone.Voice.ICEProvider

  @impl true
  def resolve(options) do
    if observer = Keyword.get(options, :observer) do
      send(observer, {:voice_ice_provider_requested, options})
    end

    case Keyword.fetch!(options, :results) do
      :wait_forever ->
        receive do
          :release_voice_ice_provider -> {:error, :unavailable}
        end

      {:raise, message} ->
        raise message

      results when is_pid(results) ->
        Agent.get_and_update(results, fn [result | remaining] -> {result, remaining} end)

      result ->
        result
    end
  end
end
