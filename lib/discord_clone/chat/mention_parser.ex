defmodule DiscordClone.Chat.MentionParser do
  @moduledoc """
  Recognizes username-shaped direct mentions in message content.

  Resolution and authorization deliberately live in the Chat context, where
  membership can be checked in the message-send transaction.
  """

  @username_pattern ~r/(?<![A-Za-z0-9_@])@([A-Za-z0-9_]{3,32})(?![A-Za-z0-9_])/u

  @doc "Returns unique, normalized username candidates in first-seen order."
  @spec usernames(term()) :: [String.t()]
  def usernames(content) when is_binary(content) do
    @username_pattern
    |> Regex.scan(content, capture: :all_but_first)
    |> List.flatten()
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end

  def usernames(_content), do: []
end
