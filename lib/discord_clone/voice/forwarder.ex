defmodule DiscordClone.Voice.Forwarder do
  @moduledoc false

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok)

  @impl true
  def init(:ok), do: {:ok, :no_routes}
end
