defmodule DiscordClone.Chat.ChannelServer do
  @moduledoc false

  use GenServer

  alias DiscordClone.Chat.ChannelRegistry

  @inactivity_timeout_ms :timer.minutes(15)
  @typing_timeout_ms :timer.seconds(5)

  def touch(pid) when is_pid(pid) do
    GenServer.call(pid, :touch)
  end

  def list_recent_messages(pid) when is_pid(pid) do
    GenServer.call(pid, :list_recent_messages)
  end

  def put_recent_message(pid, message) when is_pid(pid) do
    GenServer.call(pid, {:put_recent_message, message})
  end

  def list_typing_user_ids(pid) when is_pid(pid) do
    GenServer.call(pid, :list_typing_user_ids)
  end

  def user_started_typing(pid, user_id) when is_pid(pid) do
    GenServer.call(pid, {:user_started_typing, user_id})
  end

  def user_stopped_typing(pid, user_id) when is_pid(pid) do
    GenServer.call(pid, {:user_stopped_typing, user_id})
  end

  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]},
      restart: :temporary
    }
  end

  @spec start_link({any(), any()}) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link({channel_id, recent_messages}) do
    GenServer.start_link(__MODULE__, {channel_id, recent_messages}, name: via_tuple(channel_id))
  end

  def whereis(channel_id) do
    case Registry.lookup(ChannelRegistry, channel_id) do
      [{pid, _value}] -> if Process.alive?(pid), do: pid
      [] -> nil
    end
  end

  @impl true
  def init({channel_id, recent_messages}) do
    {:ok,
     %{
       channel_id: channel_id,
       recent_messages: recent_messages,
       typing_users: %{},
       last_activity_at: now_ms()
     }
     |> schedule_idle_timeout()}
  end

  @impl true
  def handle_call(:touch, _from, state) do
    {:reply, :ok, refresh_activity(state)}
  end

  def handle_call(:list_recent_messages, _from, state) do
    {:reply, {:ok, state.recent_messages}, refresh_activity(state)}
  end

  def handle_call({:put_recent_message, message}, _from, state) do
    recent_messages =
      state.recent_messages
      |> Enum.reject(&(&1.id == message.id))
      |> Kernel.++([message])
      |> Enum.take(-50)

    state =
      state
      |> Map.put(:recent_messages, recent_messages)
      |> refresh_activity()

    {:reply, :ok, state}
  end

  def handle_call(:list_typing_user_ids, _from, state) do
    typing_user_ids = state.typing_users |> Map.keys() |> Enum.sort()

    {:reply, {:ok, typing_user_ids}, refresh_activity(state)}
  end

  def handle_call({:user_started_typing, user_id}, _from, state) do
    already_typing? = Map.has_key?(state.typing_users, user_id)

    state =
      state
      |> put_in([:typing_users, user_id], typing_deadline_ms())
      |> refresh_activity()

    unless already_typing? do
      Phoenix.PubSub.broadcast(
        DiscordClone.PubSub,
        channel_topic(state.channel_id),
        {:typing_started, %{channel_id: state.channel_id, user_id: user_id}}
      )
    end

    {:reply, :ok, state}
  end

  def handle_call({:user_stopped_typing, user_id}, _from, state) do
    was_typing? = Map.has_key?(state.typing_users, user_id)

    state =
      state
      |> update_in([:typing_users], &Map.delete(&1, user_id))
      |> refresh_activity()

    if was_typing? do
      Phoenix.PubSub.broadcast(
        DiscordClone.PubSub,
        channel_topic(state.channel_id),
        {:typing_stopped, %{channel_id: state.channel_id, user_id: user_id}}
      )
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:idle_timeout, idle_timer_ref}, %{idle_timer_ref: idle_timer_ref} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:idle_timeout, _stale_timer_ref}, state) do
    {:noreply, state}
  end

  defp via_tuple(channel_id) do
    {:via, Registry, {ChannelRegistry, channel_id}}
  end

  defp refresh_activity(state) do
    state
    |> Map.put(:last_activity_at, now_ms())
    |> schedule_idle_timeout()
  end

  defp schedule_idle_timeout(state) do
    if timer_ref = Map.get(state, :idle_timer) do
      Process.cancel_timer(timer_ref)
    end

    idle_timer_ref = make_ref()

    idle_timer =
      Process.send_after(self(), {:idle_timeout, idle_timer_ref}, inactivity_timeout_ms())

    state
    |> Map.put(:idle_timer_ref, idle_timer_ref)
    |> Map.put(:idle_timer, idle_timer)
  end

  defp inactivity_timeout_ms do
    Application.get_env(
      :discord_clone,
      :channel_runtime_inactivity_timeout_ms,
      @inactivity_timeout_ms
    )
  end

  defp typing_deadline_ms, do: now_ms() + @typing_timeout_ms

  defp channel_topic(channel_id), do: "chat:channel:#{channel_id}"

  defp now_ms, do: System.monotonic_time(:millisecond)
end
