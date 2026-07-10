defmodule DiscordClone.UUIDIdentifier do
  @moduledoc false

  def cast(value) do
    case Ecto.UUID.cast(value) do
      {:ok, identifier} -> {:ok, identifier}
      :error -> :error
    end
  end

  def cast_all(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, identifiers} ->
      case cast(value) do
        {:ok, identifier} -> {:cont, {:ok, [identifier | identifiers]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, identifiers} -> {:ok, Enum.reverse(identifiers)}
      :error -> :error
    end
  end
end
