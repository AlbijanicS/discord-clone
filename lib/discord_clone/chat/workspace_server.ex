defmodule DiscordClone.Chat.WorkspaceServer do
  @moduledoc false

  use GenServer

  alias DiscordClone.Chat.{WorkspacePresence, WorkspaceRegistry}

  def start_link(workspace_id) do
    GenServer.start_link(__MODULE__, workspace_id, name: via_tuple(workspace_id))
  end

  def whereis(workspace_id) do
    case Registry.lookup(WorkspaceRegistry, workspace_id) do
      [{pid, _value}] -> pid
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
    {:ok, %{workspace_id: workspace_id, users: %{}, monitors: %{}}}
  end

  @impl true
  def handle_call({:join, user_id, live_view_pid}, _from, state) do
    user_was_online? = Map.has_key?(state.users, user_id)

    state =
      if tracked_pid?(state, user_id, live_view_pid) do
        state
      else
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
    {:reply, state.users |> Map.keys() |> Enum.sort(), state}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, monitor_ref) do
      {{user_id, live_view_pid}, monitors} ->
        users = remove_user_pid(state.users, user_id, live_view_pid)
        state = %{state | users: users, monitors: monitors}

        if !Map.has_key?(state.users, user_id) do
          :ok = WorkspacePresence.broadcast_user_left(state.workspace_id, user_id)
        end

        {:noreply, state}

      {nil, _monitors} ->
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
