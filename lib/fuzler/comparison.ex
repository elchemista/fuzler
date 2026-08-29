defmodule Fuzler.Comparison do
  @moduledoc """
  Detailed result returned by `Fuzler.compare/2` and `Fuzler.compare/3`.

  Component scores are rounded to two decimal places. `token_score` and
  `character_score` describe the full-input comparison. `matched_text` is the
  normalised window selected by partial matching, or `nil` when the full score
  wins.
  """

  @enforce_keys [
    :score,
    :full_score,
    :partial_score,
    :token_score,
    :character_score,
    :matched_text,
    :algorithm_version
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          score: Fuzler.score(),
          full_score: Fuzler.score(),
          partial_score: Fuzler.score(),
          token_score: Fuzler.score() | nil,
          character_score: Fuzler.score(),
          matched_text: String.t() | nil,
          algorithm_version: String.t()
        }

  @doc false
  @spec from_native(map()) :: t()
  def from_native(values), do: struct!(__MODULE__, values)
end
