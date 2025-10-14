defmodule MultiAgentCoder.Session.Storage.Session do
  @moduledoc """
  Session data structure.

  Represents a conversation session with full history and metadata.
  Graph-ready structure compatible with future Grapple integration.
  """

  @derive Jason.Encoder
  defstruct [
    :id,
    # For forked sessions
    :parent_id,
    # Message index where fork occurred
    :fork_point,
    :created_at,
    :last_accessed_at,
    :access_count,
    # List of Message structs
    :messages,
    # Tags, labels, custom data
    :metadata,
    # List of AI providers used
    :providers_used,
    # Total token usage
    :total_tokens,
    # Estimated cost in USD
    :estimated_cost,
    # :standard, :critical, :temporary
    :retention_policy
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
