defmodule DiscordClone.Voice.ForwarderTest do
  use ExUnit.Case, async: false

  alias DiscordClone.Voice.Forwarder

  test "routes only with exactly two ready Opus Sessions and restores after a third is removed" do
    attach_route_diagnostics()
    forwarder = start_forwarder()
    [first_id, second_id, third_id] = Enum.map(1..3, fn _ -> Ecto.UUID.generate() end)
    packet = ExRTP.Packet.new(<<1>>, sequence_number: 1, timestamp: 1, ssrc: 1)

    register_ready_session(forwarder, second_id, 202)
    register_ready_session(forwarder, first_id, 101)
    assert :ok = Forwarder.sync(forwarder)

    assert :ok = Forwarder.forward_rtp(forwarder, first_id, 101, packet)
    assert_receive {_cast, {:deliver_rtp, ^second_id, ^packet}}
    assert_receive {:voice_route_diagnostic, %{media_lifecycle: :rtp_forwarded} = forwarded}
    assert_route_diagnostic(forwarded, 1, 0)
    refute_receive {_cast, {:deliver_rtp, ^first_id, ^packet}}, 0

    assert :ok = Forwarder.session_started(forwarder, third_id, self())
    assert :ok = Forwarder.sync(forwarder)
    assert :ok = Forwarder.forward_rtp(forwarder, first_id, 101, packet)
    assert :ok = Forwarder.sync(forwarder)
    refute_receive {_cast, {:deliver_rtp, _, ^packet}}, 0
    assert_receive {:voice_route_diagnostic, %{media_lifecycle: :rtp_dropped} = dropped}
    assert_route_diagnostic(dropped, 1, 1)

    assert :ok = Forwarder.session_removed(forwarder, third_id)
    assert :ok = Forwarder.sync(forwarder)
    assert :ok = Forwarder.forward_rtp(forwarder, first_id, 101, packet)
    assert_receive {_cast, {:deliver_rtp, ^second_id, ^packet}}
    assert_receive {:voice_route_diagnostic, %{media_lifecycle: :rtp_forwarded} = restored}
    assert_route_diagnostic(restored, 2, 1)
  end

  test "requires complementary readiness and removes only the ended source" do
    forwarder = start_forwarder()
    first_id = Ecto.UUID.generate()
    second_id = Ecto.UUID.generate()
    packet = ExRTP.Packet.new(<<2>>, sequence_number: 2, timestamp: 2, ssrc: 2)

    assert :ok = Forwarder.session_started(forwarder, first_id, self())
    assert :ok = Forwarder.session_started(forwarder, second_id, self())
    assert :ok = Forwarder.receive_ready(forwarder, first_id, self(), :opus)
    assert :ok = Forwarder.send_ready(forwarder, first_id, self(), 101, :opus)
    assert :ok = Forwarder.send_ready(forwarder, second_id, self(), 202, :opus)
    assert :ok = Forwarder.sync(forwarder)

    assert :ok = Forwarder.forward_rtp(forwarder, first_id, 101, packet)
    assert :ok = Forwarder.sync(forwarder)
    refute_receive {_cast, {:deliver_rtp, _, ^packet}}, 0

    assert :ok = Forwarder.receive_ready(forwarder, second_id, self(), :opus)
    assert :ok = Forwarder.sync(forwarder)
    assert :ok = Forwarder.forward_rtp(forwarder, first_id, 101, packet)
    assert_receive {_cast, {:deliver_rtp, ^second_id, ^packet}}

    assert :ok = Forwarder.source_ended(forwarder, first_id, self(), 101)
    assert :ok = Forwarder.sync(forwarder)
    assert :ok = Forwarder.forward_rtp(forwarder, first_id, 101, packet)
    assert :ok = Forwarder.sync(forwarder)
    refute_receive {_cast, {:deliver_rtp, _, ^packet}}, 0

    assert :ok = Forwarder.forward_rtp(forwarder, second_id, 202, packet)
    assert_receive {_cast, {:deliver_rtp, ^first_id, ^packet}}
  end

  defp start_forwarder do
    start_supervised!({Forwarder, voice_channel_id: Ecto.UUID.generate()})
  end

  defp register_ready_session(forwarder, voice_session_id, track_id) do
    assert :ok = Forwarder.session_started(forwarder, voice_session_id, self())
    assert :ok = Forwarder.receive_ready(forwarder, voice_session_id, self(), :opus)
    assert :ok = Forwarder.send_ready(forwarder, voice_session_id, self(), track_id, :opus)
  end

  defp attach_route_diagnostics do
    handler_id = "voice-route-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:discord_clone, :voice_signaling, :operation],
        fn _, _, metadata, _ ->
          if metadata[:media_lifecycle] in [:rtp_forwarded, :rtp_dropped] do
            send(test_pid, {:voice_route_diagnostic, metadata})
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp assert_route_diagnostic(metadata, forwarded_count, dropped_count) do
    assert metadata == %{
             media_lifecycle: metadata.media_lifecycle,
             forwarded_packet_count: forwarded_count,
             dropped_packet_count: dropped_count
           }
  end
end
