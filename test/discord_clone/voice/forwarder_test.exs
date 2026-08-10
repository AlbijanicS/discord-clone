defmodule DiscordClone.Voice.ForwarderTest do
  use ExUnit.Case, async: false

  alias DiscordClone.Voice.Forwarder

  test "routes the complete three-Session matrix without blocking ready pairs" do
    attach_route_diagnostics()
    forwarder = start_forwarder()
    [first_id, second_id, third_id] = Enum.map(1..3, fn _ -> Ecto.UUID.generate() end)
    first_packet = ExRTP.Packet.new(<<1>>, sequence_number: 1, timestamp: 1, ssrc: 1)

    register_ready_session(forwarder, second_id, 202)
    register_ready_session(forwarder, first_id, 101)
    assert :ok = Forwarder.sync(forwarder)

    assert :ok = Forwarder.forward_rtp(forwarder, first_id, 101, first_packet)
    assert_receive {_cast, {:deliver_rtp, ^second_id, 0, ^first_packet}}
    assert_receive {:voice_route_diagnostic, %{media_lifecycle: :rtp_forwarded} = forwarded}
    assert_route_diagnostic(forwarded, 1, 0)
    refute_receive {_cast, {:deliver_rtp, ^first_id, _, ^first_packet}}, 0

    assert :ok = Forwarder.session_started(forwarder, third_id, self())
    assert :ok = Forwarder.sync(forwarder)
    assert :ok = Forwarder.forward_rtp(forwarder, first_id, 101, first_packet)
    assert_receive {_cast, {:deliver_rtp, ^second_id, 0, ^first_packet}}
    refute_receive {_cast, {:deliver_rtp, ^third_id, _, ^first_packet}}, 0

    assert :ok = Forwarder.receive_ready(forwarder, third_id, self(), :opus)
    assert :ok = Forwarder.send_ready(forwarder, third_id, self(), 303, :opus)
    assert :ok = Forwarder.sync(forwarder)

    source_packets = [
      {first_id, 101, ExRTP.Packet.new(<<11>>, sequence_number: 11, timestamp: 11, ssrc: 11)},
      {second_id, 202, ExRTP.Packet.new(<<22>>, sequence_number: 22, timestamp: 22, ssrc: 22)},
      {third_id, 303, ExRTP.Packet.new(<<33>>, sequence_number: 33, timestamp: 33, ssrc: 33)}
    ]

    deliveries =
      Enum.flat_map(source_packets, fn {source_id, track_id, packet} ->
        assert :ok = Forwarder.forward_rtp(forwarder, source_id, track_id, packet)

        Enum.map(1..2, fn _ ->
          assert_receive {_cast, {:deliver_rtp, destination_id, slot, ^packet}}
          {source_id, destination_id, slot}
        end)
      end)

    assert MapSet.new(
             Enum.map(deliveries, fn {source_id, destination_id, _slot} ->
               {source_id, destination_id}
             end)
           ) ==
             MapSet.new([
               {first_id, second_id},
               {first_id, third_id},
               {second_id, first_id},
               {second_id, third_id},
               {third_id, first_id},
               {third_id, second_id}
             ])

    for destination_id <- [first_id, second_id, third_id] do
      destination_slots =
        for {_source_id, ^destination_id, slot} <- deliveries, do: slot

      assert Enum.sort(destination_slots) == [0, 1]
    end
  end

  test "duplicate readiness in a different order keeps each source in its destination slot" do
    forwarder = start_forwarder()
    [first_id, second_id, third_id] = Enum.map(1..3, fn _ -> Ecto.UUID.generate() end)

    for voice_session_id <- [first_id, second_id, third_id] do
      assert :ok = Forwarder.session_started(forwarder, voice_session_id, self())
    end

    for {voice_session_id, track_id} <- [{third_id, 303}, {first_id, 101}, {second_id, 202}] do
      assert :ok = Forwarder.send_ready(forwarder, voice_session_id, self(), track_id, :opus)
      assert :ok = Forwarder.receive_ready(forwarder, voice_session_id, self(), :opus)
    end

    assert :ok = Forwarder.sync(forwarder)
    packet = ExRTP.Packet.new(<<4>>, sequence_number: 4, timestamp: 4, ssrc: 4)
    assert :ok = Forwarder.forward_rtp(forwarder, third_id, 303, packet)

    first_deliveries =
      Enum.map(1..2, fn _ ->
        assert_receive {_cast, {:deliver_rtp, destination_id, slot, ^packet}}
        {destination_id, slot}
      end)

    assert :ok = Forwarder.receive_ready(forwarder, third_id, self(), :opus)
    assert :ok = Forwarder.send_ready(forwarder, third_id, self(), 303, :opus)
    assert :ok = Forwarder.sync(forwarder)
    assert :ok = Forwarder.forward_rtp(forwarder, third_id, 303, packet)

    second_deliveries =
      Enum.map(1..2, fn _ ->
        assert_receive {_cast, {:deliver_rtp, destination_id, slot, ^packet}}
        {destination_id, slot}
      end)

    assert MapSet.new(second_deliveries) == MapSet.new(first_deliveries)
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
    refute_receive {_cast, {:deliver_rtp, _, _, ^packet}}, 0

    assert :ok = Forwarder.receive_ready(forwarder, second_id, self(), :opus)
    assert :ok = Forwarder.sync(forwarder)
    assert :ok = Forwarder.forward_rtp(forwarder, first_id, 101, packet)
    assert_receive {_cast, {:deliver_rtp, ^second_id, 0, ^packet}}

    assert :ok = Forwarder.source_ended(forwarder, first_id, self(), 101)
    assert :ok = Forwarder.sync(forwarder)
    assert :ok = Forwarder.forward_rtp(forwarder, first_id, 101, packet)
    assert :ok = Forwarder.sync(forwarder)
    refute_receive {_cast, {:deliver_rtp, _, _, ^packet}}, 0

    assert :ok = Forwarder.forward_rtp(forwarder, second_id, 202, packet)
    assert_receive {_cast, {:deliver_rtp, ^first_id, 0, ^packet}}
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
