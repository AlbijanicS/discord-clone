defmodule DiscordClone.Chat.ChannelSupervisor do
  @moduledoc false

  import Ecto.Query

  alias DiscordClone.Chat.{ChannelServer, Message}
  alias DiscordClone.Repo

  @recent_message_limit 50

  def start_channel(channel_id) do
    case ChannelServer.whereis(channel_id) do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        recent_messages = load_recent_messages(channel_id)

        case DynamicSupervisor.start_child(
               __MODULE__,
               {ChannelServer, {channel_id, recent_messages}}
             ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp load_recent_messages(channel_id) do
    Message
    |> where([message], message.channel_id == ^channel_id)
    |> order_by([message], desc: message.inserted_at, desc: message.id)
    |> limit(^@recent_message_limit)
    |> preload(:user)
    |> Repo.all()
    |> Enum.reverse()
  end
end
