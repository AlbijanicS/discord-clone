defmodule DiscordClone.Chat.WorkspaceServer do
  @moduledoc false

  use GenServer

  alias DiscordClone.Chat.{WorkspacePresence, WorkspaceRegistry}

  @disconnect_grace_ms 50

  def start_link(workspace_id) do
    GenServer.start_link(__MODULE__, workspace_id, name: via_tuple(workspace_id))
  end

  def whereis(workspace_id) do
    case Registry.lookup(WorkspaceRegistry, workspace_id) do
      [{pid, _value}] -> if Process.alive?(pid), do: pid
      [] -> nil
    end
  end

  def join(server, user_id, live_view_pid) when is_pid(live_view_pid) do
    GenServer.call(server, {:join, user_id, live_view_pid})
  end

  def online_user_ids(server) do
    GenServer.call(server, :online_user_ids)
  end

  @impl true
  def init(workspace_id) do
    {:ok, %{workspace_id: workspace_id, users: %{}, monitors: %{}, pending_left_timers: %{}}}
  end

  @impl true
  def handle_call({:join, user_id, live_view_pid}, _from, state) do
    user_was_online? = user_online?(state, user_id)

    state =
      if tracked_pid?(state, user_id, live_view_pid) do
        state
      else
        state = cancel_pending_left(state, user_id)
        monitor_ref = Process.monitor(live_view_pid)

        users =
          Map.update(
            state.users,
            user_id,
            MapSet.new([live_view_pid]),
            &MapSet.put(&1, live_view_pid)
          )

        monitors = Map.put(state.monitors, monitor_ref, {user_id, live_view_pid})

        %{state | users: users, monitors: monitors}
      end

    if !user_was_online? and Map.has_key?(state.users, user_id) do
      :ok = WorkspacePresence.broadcast_user_joined(state.workspace_id, user_id)
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:online_user_ids, _from, state) do
    online_user_ids =
      state.users
      |> Map.keys()
      |> Enum.concat(Map.keys(state.pending_left_timers))
      |> Enum.uniq()
      |> Enum.sort()

    {:reply, online_user_ids, state}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, monitor_ref) do
      {{user_id, live_view_pid}, monitors} ->
        users = remove_user_pid(state.users, user_id, live_view_pid)
        state = %{state | users: users, monitors: monitors}

        if !Map.has_key?(state.users, user_id) do
          state = schedule_pending_left(state, user_id)
          {:noreply, state}
        else
          {:noreply, state}
        end

      {nil, _monitors} ->
        {:noreply, state}
    end
  end

  def handle_info({:broadcast_user_left, user_id, token}, state) do
    case Map.get(state.pending_left_timers, user_id) do
      {_timer_ref, ^token} ->
        state = %{state | pending_left_timers: Map.delete(state.pending_left_timers, user_id)}

        if Map.has_key?(state.users, user_id) do
          {:noreply, state}
        else
          :ok = WorkspacePresence.broadcast_user_left(state.workspace_id, user_id)
          {:noreply, state}
        end

      _other_timer ->
        {:noreply, state}
    end
  end

  defp via_tuple(workspace_id) do
    {:via, Registry, {WorkspaceRegistry, workspace_id}}
  end

  defp tracked_pid?(state, user_id, live_view_pid) do
    state.users
    |> Map.get(user_id, MapSet.new())
    |> MapSet.member?(live_view_pid)
  end

  defp user_online?(state, user_id) do
    Map.has_key?(state.users, user_id) or Map.has_key?(state.pending_left_timers, user_id)
  end

  defp schedule_pending_left(state, user_id) do
    state = cancel_pending_left(state, user_id)
    token = make_ref()

    timer_ref =
      Process.send_after(self(), {:broadcast_user_left, user_id, token}, @disconnect_grace_ms)

    %{
      state
      | pending_left_timers: Map.put(state.pending_left_timers, user_id, {timer_ref, token})
    }
  end

  defp cancel_pending_left(state, user_id) do
    case Map.pop(state.pending_left_timers, user_id) do
      {nil, _pending_left_timers} ->
        state

      {{timer_ref, _token}, pending_left_timers} ->
        Process.cancel_timer(timer_ref)
        %{state | pending_left_timers: pending_left_timers}
    end
  end

  defp remove_user_pid(users, user_id, live_view_pid) do
    case Map.fetch(users, user_id) do
      {:ok, pids} ->
        pids = MapSet.delete(pids, live_view_pid)

        if MapSet.size(pids) == 0 do
          Map.delete(users, user_id)
        else
          Map.put(users, user_id, pids)
        end

      :error ->
        users
    end
  end
end
