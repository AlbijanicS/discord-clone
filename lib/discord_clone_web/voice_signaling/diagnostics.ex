defmodule DiscordCloneWeb.VoiceSignaling.Diagnostics do
  @moduledoc false

  alias DiscordClone.Voice.Diagnostics, as: RuntimeDiagnostics

  defdelegate emit(operation, outcome, options \\ []), to: RuntimeDiagnostics
  defdelegate emit_media(lifecycle, counts), to: RuntimeDiagnostics
end
