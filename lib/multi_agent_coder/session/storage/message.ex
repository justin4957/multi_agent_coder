defmodule MultiAgentCoder.Session.Storage.Message do
  @moduledoc """
  Message data structure.

  Represents a single message in a conversation session.
  """

  @derive Jason.Encoder
  defstruct [
    :id,
    :session_id,
    :role,                   # :user, :assistant, :system
    :content,
    :provider,               # Which AI provider generated this
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
