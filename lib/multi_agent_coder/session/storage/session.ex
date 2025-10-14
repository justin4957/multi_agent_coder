defmodule MultiAgentCoder.Session.Storage.Session do
  @moduledoc """
  Session data structure.

  Represents a conversation session with full history and metadata.
  Graph-ready structure compatible with future Grapple integration.
  """

  @derive Jason.Encoder
  defstruct [
    :id,
    :parent_id,              # For forked sessions
    :fork_point,             # Message index where fork occurred
    :created_at,
    :last_accessed_at,
    :access_count,
    :messages,               # List of Message structs
    :metadata,               # Tags, labels, custom data
    :providers_used,         # List of AI providers used
    :total_tokens,           # Total token usage
    :estimated_cost,         # Estimated cost in USD
    :retention_policy        # :standard, :critical, :temporary
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    parent_id: String.t() | nil,
    fork_point: non_neg_integer() | nil,
    created_at: DateTime.t(),
    last_accessed_at: DateTime.t(),
    access_count: non_neg_integer(),
    messages: list(MultiAgentCoder.Session.Storage.Message.t()),
    metadata: map(),
    providers_used: list(atom()),
    total_tokens: non_neg_integer(),
    estimated_cost: float(),
    retention_policy: atom()
  }
end
