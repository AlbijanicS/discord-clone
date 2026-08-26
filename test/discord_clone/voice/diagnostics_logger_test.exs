defmodule DiscordClone.Voice.DiagnosticsLoggerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias DiscordClone.Voice.Diagnostics

  test "logs bounded Voice failures without caller-supplied secrets" do
    secret = "temporary-turn-credential-that-must-not-be-logged"

    logs =
      capture_log(fn ->
        Diagnostics.emit("connection_state", :accepted,
          connection_state: :failed,
          provider_secret: secret
        )
      end)

    assert logs =~ "Voice diagnostic operation=connection_state"
    assert logs =~ "connection_state=failed"
    refute logs =~ secret
  end

  test "restarts after an abnormal exit leaves the telemetry handler attached" do
    original_pid = Process.whereis(DiscordClone.Voice.DiagnosticsLogger)
    monitor_ref = Process.monitor(original_pid)

    Process.exit(original_pid, :kill)

    assert_receive {:DOWN, ^monitor_ref, :process, ^original_pid, :killed}
    _ = :sys.get_state(DiscordCloneWeb.Telemetry)

    restarted_pid = Process.whereis(DiscordClone.Voice.DiagnosticsLogger)
    assert is_pid(restarted_pid)
    assert restarted_pid != original_pid
  end
end
