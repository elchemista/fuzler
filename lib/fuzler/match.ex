defmodule Fuzler.Match do
  @moduledoc "A ranked value returned by `Fuzler.top_matches/3` and `Fuzler.top_matches/4`."

  @enforce_keys [:value, :score, :index]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          value: String.t(),
          score: Fuzler.score(),
          index: non_neg_integer()
        }
end
