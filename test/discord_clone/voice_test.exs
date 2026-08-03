defmodule DiscordClone.VoiceTest do
  use DiscordClone.DataCase, async: false

  alias DiscordClone.Voice

  describe "room runtime lifecycle" do
    test "starts a room for a durable Voice Channel ID without exposing its process" do
      voice_channel_id = Ecto.UUID.generate()

      assert :ok = Voice.ensure_room(voice_channel_id)
      assert Voice.room_running?(voice_channel_id)
    end

    test "reuses one running room when the same Voice Channel is requested concurrently" do
      voice_channel_id = Ecto.UUID.generate()

      results =
        1..8
        |> Task.async_stream(fn _ -> Voice.ensure_room(voice_channel_id) end,
          max_concurrency: 8,
          timeout: :infinity
        )
        |> Enum.to_list()

      assert Enum.all?(results, &(&1 == {:ok, :ok}))
      assert Voice.room_running?(voice_channel_id)
    end

    test "retires an empty room after its idle grace" do
      voice_channel_id = Ecto.UUID.generate()

      assert :ok = Voice.ensure_room(voice_channel_id)
      room_server = room_server(voice_channel_id)
      ref = Process.monitor(room_server)

      assert :ok = Voice.mark_room_empty(voice_channel_id, idle_timeout: 0)
      assert_receive {:DOWN, ^ref, :process, ^room_server, :normal}
      refute Voice.room_running?(voice_channel_id)
    end

    test "new room use cancels a pending idle shutdown" do
      voice_channel_id = Ecto.UUID.generate()

      assert :ok = Voice.ensure_room(voice_channel_id)
      room_server = room_server(voice_channel_id)
      ref = Process.monitor(room_server)

      assert :ok = Voice.mark_room_empty(voice_channel_id, idle_timeout: 25)
      assert :ok = Voice.mark_room_in_use(voice_channel_id)
      _ = :sys.get_state(room_server)

      refute_receive {:DOWN, ^ref, :process, ^room_server, _reason}, 50
      assert Voice.room_running?(voice_channel_id)

      assert :ok = Voice.mark_room_empty(voice_channel_id, idle_timeout: 0)
      assert_receive {:DOWN, ^ref, :process, ^room_server, :normal}
    end

    test "malformed IDs do not start rooms" do
      assert Voice.ensure_room("not-a-uuid") == {:error, :not_found}
      refute Voice.room_running?("not-a-uuid")
      assert Voice.mark_room_in_use("not-a-uuid") == {:error, :not_found}
      assert Voice.mark_room_empty("not-a-uuid") == {:error, :not_found}
    end

    test "retries safely after a room process dies during lookup" do
      voice_channel_id = Ecto.UUID.generate()

      assert :ok = Voice.ensure_room(voice_channel_id)
      room_server = room_server(voice_channel_id)
      ref = Process.monitor(room_server)
      Process.exit(room_server, :kill)

      assert_receive {:DOWN, ^ref, :process, ^room_server, :killed}
      assert :ok = Voice.ensure_room(voice_channel_id)
      assert Voice.room_running?(voice_channel_id)
    end
  end

  defp room_server(voice_channel_id) do
    {:via, Registry, {DiscordClone.Voice.RoomRegistry, {:room, voice_channel_id}}}
    |> GenServer.whereis()
  end
end
