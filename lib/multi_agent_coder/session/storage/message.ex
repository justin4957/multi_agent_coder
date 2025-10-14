defmodule MultiAgentCoder.Session.Storage.Message do
  @moduledoc """
  Message data structure.

  Represents a single message in a conversation session.
  """

  @derive Jason.Encoder
  defstruct [
    :id,
    :session_id,
    # :user, :assistant, :system
    :role,
    :content,
    # Which AI provider generated this
    :provider,
    :timestamp,
    :tokens,
    :metadata
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          session_id: String.t(),
          role: atom(),
          content: String.t(),
          provider: atom() | nil,
          timestamp: DateTime.t(),
          tokens: non_neg_integer(),
          metadata: map()
        }
end
