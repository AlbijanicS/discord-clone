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

    test "a RoomServer failure clears its room and preserves an unrelated room" do
      affected_voice_channel_id = Ecto.UUID.generate()
      unaffected_voice_channel_id = Ecto.UUID.generate()
      affected_user_ids = Enum.map(1..2, fn _ -> Ecto.UUID.generate() end)

      for {user_id, number} <- Enum.with_index(affected_user_ids, 1) do
        assert {:ok, %{occupancy: ^number}} =
                 Voice.admit(
                   affected_voice_channel_id,
                   user_id,
                   "affected-connection-#{number}",
                   self()
                 )
      end

      assert {:ok, %{occupancy: 1}} =
               Voice.admit(
                 unaffected_voice_channel_id,
                 Ecto.UUID.generate(),
                 "unaffected-connection-1",
                 self()
               )

      room_server = room_server(affected_voice_channel_id)
      room_ref = Process.monitor(room_server)
      Process.exit(room_server, :kill)

      assert_receive {:DOWN, ^room_ref, :process, ^room_server, :killed}

      for {user_id, number} <- Enum.with_index(affected_user_ids, 1) do
        assert {:ok, %{occupancy: ^number}} =
                 Voice.admit(
                   affected_voice_channel_id,
                   user_id,
                   "rejoin-after-room-failure-#{number}",
                   self()
                 )
      end

      assert {:ok, %{occupancy: 1, capacity: 5}} =
               Voice.room_occupancy(unaffected_voice_channel_id)
    end

    test "a Forwarder failure clears its room and preserves an unrelated room" do
      affected_voice_channel_id = Ecto.UUID.generate()
      unaffected_voice_channel_id = Ecto.UUID.generate()
      affected_user_id = Ecto.UUID.generate()

      assert {:ok, %{occupancy: 1}} =
               Voice.admit(
                 affected_voice_channel_id,
                 affected_user_id,
                 "affected-connection-1",
                 self()
               )

      assert {:ok, %{occupancy: 1}} =
               Voice.admit(
                 unaffected_voice_channel_id,
                 Ecto.UUID.generate(),
                 "unaffected-connection-1",
                 self()
               )

      assert :ok = Voice.crash_forwarder(affected_voice_channel_id)

      assert {:ok, %{occupancy: 1}} =
               Voice.admit(
                 affected_voice_channel_id,
                 affected_user_id,
                 "rejoin-after-forwarder-failure",
                 self()
               )

      assert {:ok, %{occupancy: 1, capacity: 5}} =
               Voice.room_occupancy(unaffected_voice_channel_id)
    end

    test "late cleanup for a failed room cannot clear a rejoined Voice Session" do
      voice_channel_id = Ecto.UUID.generate()
      replacement_voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: old_voice_session_id}} =
               Voice.admit(voice_channel_id, user_id, "same-signaling-session", self())

      room_server = room_server(voice_channel_id)
      room_ref = Process.monitor(room_server)
      Process.exit(room_server, :kill)

      assert_receive {:DOWN, ^room_ref, :process, ^room_server, :killed}

      assert {:ok, %{voice_session_id: new_voice_session_id, occupancy: 1}} =
               Voice.admit(voice_channel_id, user_id, "same-signaling-session", self())

      refute new_voice_session_id == old_voice_session_id
      assert :ok = Voice.leave(voice_channel_id, old_voice_session_id)

      assert {:ok, _admission} =
               Voice.admit(replacement_voice_channel_id, user_id, "replacement-session", self())

      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(voice_channel_id)

      assert {:ok, %{occupancy: 1, capacity: 5}} =
               Voice.room_occupancy(replacement_voice_channel_id)
    end

    test "AdmissionServer restart retires old rooms before accepting fresh admissions" do
      voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: old_voice_session_id}} =
               Voice.admit(voice_channel_id, user_id, "before-coordinator-restart", self())

      room_server = room_server(voice_channel_id)
      room_ref = Process.monitor(room_server)
      admission_server = Process.whereis(DiscordClone.Voice.AdmissionServer)
      admission_ref = Process.monitor(admission_server)

      assert :ok = Voice.crash_admission_server()
      assert_receive {:DOWN, ^admission_ref, :process, ^admission_server, :killed}
      assert_receive {:DOWN, ^room_ref, :process, ^room_server, _reason}
      assert :ok = Voice.await_admission_recovery()
      refute Voice.room_running?(voice_channel_id)

      assert {:ok, %{voice_session_id: new_voice_session_id, occupancy: 1}} =
               Voice.admit(voice_channel_id, user_id, "after-coordinator-restart", self())

      refute new_voice_session_id == old_voice_session_id
    end
  end

  describe "room-local Voice Session admission" do
    test "admits a Voice Session with a fresh opaque ID" do
      voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, admission} =
               Voice.admit(voice_channel_id, user_id, "signaling-connection-1", self())

      assert %{voice_session_id: voice_session_id, occupancy: 1, capacity: 5} = admission
      assert {:ok, ^voice_session_id} = Ecto.UUID.cast(voice_session_id)
      refute voice_session_id in [voice_channel_id, user_id, "signaling-connection-1"]
      refute inspect(admission) =~ "#PID"
    end

    test "reuses the existing admission for the same signaling connection" do
      voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, first} = Voice.admit(voice_channel_id, user_id, "connection-1", self())
      assert {:ok, repeated} = Voice.admit(voice_channel_id, user_id, "connection-1", self())

      assert repeated == first
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(voice_channel_id)
    end

    test "atomically caps a room at five concurrent Voice Sessions" do
      voice_channel_id = Ecto.UUID.generate()

      signaling_channels = Enum.map(1..6, &start_signaling_channel/1)

      results =
        1..5
        |> Task.async_stream(
          fn number ->
            Voice.admit(
              voice_channel_id,
              Ecto.UUID.generate(),
              "connection-#{number}",
              Enum.at(signaling_channels, number - 1)
            )
          end,
          max_concurrency: 5,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.all?(results, &match?({:ok, %{occupancy: _, capacity: 5}}, &1))

      assert {:error, %{reason: :room_full, occupancy: 5, capacity: 5} = room_full} =
               Voice.admit(
                 voice_channel_id,
                 Ecto.UUID.generate(),
                 "connection-6",
                 Enum.at(signaling_channels, 5)
               )

      assert Map.keys(room_full) |> Enum.sort() == [:capacity, :occupancy, :reason]
    end

    test "leave is idempotent and the final leave begins empty-room cleanup" do
      voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: voice_session_id}} =
               Voice.admit(voice_channel_id, user_id, "connection-1", self())

      assert :ok = Voice.leave(voice_channel_id, voice_session_id)
      assert :ok = Voice.leave(voice_channel_id, voice_session_id)
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(voice_channel_id)

      assert :ok = Voice.expire_idle_room(voice_channel_id)
      refute Voice.room_running?(voice_channel_id)
    end

    test "a crashed temporary Session removes only its own membership" do
      voice_channel_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: crashed_session_id}} =
               Voice.admit(voice_channel_id, Ecto.UUID.generate(), "connection-1", self())

      assert {:ok, %{voice_session_id: healthy_session_id}} =
               Voice.admit(voice_channel_id, Ecto.UUID.generate(), "connection-2", self())

      assert :ok = Voice.crash_session(voice_channel_id, crashed_session_id)

      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(voice_channel_id)

      assert {:ok, %{voice_session_id: replacement_session_id}} =
               Voice.admit(voice_channel_id, Ecto.UUID.generate(), "connection-1", self())

      refute replacement_session_id == crashed_session_id

      assert :ok = Voice.leave(voice_channel_id, replacement_session_id)
      assert :ok = Voice.leave(voice_channel_id, healthy_session_id)
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(voice_channel_id)
    end

    test "a signaling channel death removes its Voice Session" do
      voice_channel_id = Ecto.UUID.generate()

      signaling_channel = start_signaling_channel(:connection_death)

      assert {:ok, _admission} =
               Voice.admit(
                 voice_channel_id,
                 Ecto.UUID.generate(),
                 "connection-1",
                 signaling_channel
               )

      Process.exit(signaling_channel, :shutdown)

      assert :ok = Voice.await_empty_room(voice_channel_id)
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(voice_channel_id)
    end
  end

  describe "cross-room Voice Session admission" do
    test "serializes concurrent admission requests for one User into one active Voice Session" do
      user_id = Ecto.UUID.generate()
      voice_channel_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]
      signaling_channels = Enum.map(1..8, &start_signaling_channel/1)

      results =
        0..7
        |> Task.async_stream(
          fn number ->
            Voice.admit(
              Enum.at(voice_channel_ids, rem(number, 2)),
              user_id,
              "connection-#{number}",
              Enum.at(signaling_channels, number)
            )
          end,
          max_concurrency: 8,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.all?(results, &match?({:ok, %{voice_session_id: _}}, &1))

      total_occupancy =
        Enum.reduce(voice_channel_ids, 0, fn voice_channel_id, total ->
          case Voice.room_occupancy(voice_channel_id) do
            {:ok, %{occupancy: occupancy}} -> total + occupancy
            {:error, :not_found} -> total
          end
        end)

      assert total_occupancy == 1
    end

    test "moves a User to an available Voice Channel and retires the old Voice Session" do
      first_voice_channel_id = Ecto.UUID.generate()
      second_voice_channel_id = Ecto.UUID.generate()
      third_voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: first_voice_session_id}} =
               Voice.admit(first_voice_channel_id, user_id, "connection-1", self())

      assert {:ok, %{voice_session_id: second_voice_session_id}} =
               Voice.admit(second_voice_channel_id, user_id, "connection-2", self())

      refute second_voice_session_id == first_voice_session_id
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(first_voice_channel_id)
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(second_voice_channel_id)
      assert :ok = Voice.leave(first_voice_channel_id, first_voice_session_id)

      assert {:ok, %{voice_session_id: third_voice_session_id}} =
               Voice.admit(third_voice_channel_id, user_id, "connection-3", self())

      refute third_voice_session_id == second_voice_session_id
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(second_voice_channel_id)
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(third_voice_channel_id)
    end

    test "clears an explicitly left Voice Session from global coordination" do
      first_voice_channel_id = Ecto.UUID.generate()
      second_voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: voice_session_id}} =
               Voice.admit(first_voice_channel_id, user_id, "connection-1", self())

      assert :ok = Voice.leave(first_voice_channel_id, voice_session_id)

      assert {:ok, _admission} =
               Voice.admit(second_voice_channel_id, user_id, "connection-2", self())

      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(first_voice_channel_id)
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(second_voice_channel_id)
    end

    test "ignores a leave with the wrong Voice Channel ID" do
      first_voice_channel_id = Ecto.UUID.generate()
      wrong_voice_channel_id = Ecto.UUID.generate()
      second_voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: voice_session_id}} =
               Voice.admit(first_voice_channel_id, user_id, "connection-1", self())

      assert :ok = Voice.leave(wrong_voice_channel_id, voice_session_id)

      assert {:ok, _admission} =
               Voice.admit(second_voice_channel_id, user_id, "connection-2", self())

      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(first_voice_channel_id)
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(second_voice_channel_id)
    end

    test "preserves the current Voice Session when a move target is full" do
      first_voice_channel_id = Ecto.UUID.generate()
      full_voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: current_voice_session_id}} =
               Voice.admit(first_voice_channel_id, user_id, "connection-1", self())

      full_signaling_channels = Enum.map(1..5, &start_signaling_channel/1)

      for number <- 1..5 do
        assert {:ok, _admission} =
                 Voice.admit(
                   full_voice_channel_id,
                   Ecto.UUID.generate(),
                   "full-connection-#{number}",
                   Enum.at(full_signaling_channels, number - 1)
                 )
      end

      assert {:error, %{reason: :room_full, occupancy: 5, capacity: 5}} =
               Voice.admit(full_voice_channel_id, user_id, "connection-2", self())

      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(first_voice_channel_id)
      assert {:ok, %{occupancy: 5, capacity: 5}} = Voice.room_occupancy(full_voice_channel_id)
      assert :ok = Voice.leave(first_voice_channel_id, current_voice_session_id)
    end

    test "clears a failed Voice Session from global coordination before a replacement admission" do
      first_voice_channel_id = Ecto.UUID.generate()
      second_voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: crashed_voice_session_id}} =
               Voice.admit(first_voice_channel_id, user_id, "connection-1", self())

      assert :ok = Voice.crash_session(first_voice_channel_id, crashed_voice_session_id)

      assert {:ok, %{voice_session_id: replacement_voice_session_id}} =
               Voice.admit(second_voice_channel_id, user_id, "connection-2", self())

      refute replacement_voice_session_id == crashed_voice_session_id
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(first_voice_channel_id)
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(second_voice_channel_id)
    end
  end

  defp room_server(voice_channel_id) do
    {:via, Registry, {DiscordClone.Voice.RoomRegistry, {:room, voice_channel_id}}}
    |> GenServer.whereis()
  end

  defp start_signaling_channel(id) do
    start_supervised!(%{
      id: {:voice_signaling_channel, id},
      start:
        {Task, :start_link,
         [
           fn ->
             receive do
               :stop -> :ok
             end
           end
         ]}
    })
  end
end
