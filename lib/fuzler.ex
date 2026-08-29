defmodule Fuzler do
  @moduledoc """
  Fast, configurable lexical similarity scoring for UTF-8 text.

  Fuzler combines token overlap, grapheme-aware edit distance, and bounded
  partial matching in a Rust NIF scheduled on a dirty CPU scheduler.

  `similarity_score/2` is the compact API. `compare/2` explains the component
  scores, while `similarity_scores/2` and `top_matches/3` process collections
  with a single native call.

  ## Examples

      iex> Fuzler.similarity_score("Hello, WORLD!", "hello world")
      1.0

      iex> Fuzler.similarity_score("bella ciao", "ciao bella")
      0.7

      iex> Fuzler.similarity_score("café", "cafe\u0301")
      1.0

      iex> comparison = Fuzler.compare("needle", "some text with needle inside")
      iex> comparison.score
      0.6

      iex> Fuzler.top_matches("milano", ["Roma", "Milano", "Milano Centrale"], 2)
      [
        %Fuzler.Match{value: "Milano", score: 1.0, index: 1},
        %Fuzler.Match{value: "Milano Centrale", score: 0.75, index: 2}
      ]

  Scores are symmetric, rounded to two decimal places, and always in
  `0.0..1.0`. Fuzler measures lexical similarity; it does not understand
  synonyms or semantic meaning.
  """

  alias Fuzler.{Comparison, Match, Options}

  @algorithm_version "1"

  @typedoc "A similarity value in the inclusive range `0.0..1.0`."
  @type score :: float()

  @doc "Returns the version of the scoring algorithm used by this release."
  @spec algorithm_version() :: String.t()
  def algorithm_version, do: @algorithm_version

  @doc """
  Returns the lexical similarity between two UTF-8 strings.

  See `Fuzler.Options` for the accepted options. The two-argument form uses
  the documented defaults.
  """
  @spec similarity_score(String.t(), String.t()) :: score()
  @spec similarity_score(String.t(), String.t(), [Options.option()]) :: score()
  def similarity_score(query, target, options \\ [])

  def similarity_score(query, target, options)
      when is_binary(query) and is_binary(target) and is_list(options) do
    validated = Options.validate!(options)
    validate_input!(query, validated, "query")
    validate_input!(target, validated, "target")

    query
    |> Fuzler.Native.similarity_score(target, Options.to_native(validated))
    |> unwrap_native!()
  end

  @doc """
  Returns a detailed breakdown of a comparison.

  `token_score` is `nil` when both normalised inputs contain a single token.
  `matched_text` contains the normalised target window when partial matching
  wins over the full-string score.
  """
  @spec compare(String.t(), String.t()) :: Comparison.t()
  @spec compare(String.t(), String.t(), [Options.option()]) :: Comparison.t()
  def compare(query, target, options \\ [])

  def compare(query, target, options)
      when is_binary(query) and is_binary(target) and is_list(options) do
    validated = Options.validate!(options)
    validate_input!(query, validated, "query")
    validate_input!(target, validated, "target")

    query
    |> Fuzler.Native.compare(target, Options.to_native(validated))
    |> unwrap_native!()
    |> Comparison.from_native()
  end

  @doc """
  Scores every target against one query in a single dirty-CPU NIF call.

  The returned scores preserve the input order. The batch is limited by the
  `:max_batch_size` option.
  """
  @spec similarity_scores(String.t(), [String.t()]) :: [score()]
  @spec similarity_scores(String.t(), [String.t()], [Options.option()]) :: [score()]
  def similarity_scores(query, targets, options \\ [])

  def similarity_scores(query, targets, options)
      when is_binary(query) and is_list(targets) and is_list(options) do
    validated = Options.validate!(options)
    validate_input!(query, validated, "query")
    validate_targets!(query, targets, validated)

    query
    |> Fuzler.Native.similarity_scores(targets, Options.to_native(validated))
    |> unwrap_native!()
  end

  @doc """
  Returns the best `limit` targets ordered by descending similarity.

  Equal scores retain input order. Each `%Fuzler.Match{}` includes the
  original value and its zero-based input index.
  """
  @spec top_matches(String.t(), [String.t()], non_neg_integer()) :: [Match.t()]
  @spec top_matches(String.t(), [String.t()], non_neg_integer(), [Options.option()]) :: [
          Match.t()
        ]
  def top_matches(query, targets, limit, options \\ [])

  def top_matches(query, targets, limit, options)
      when is_binary(query) and is_list(targets) and is_integer(limit) and limit >= 0 and
             is_list(options) do
    query
    |> similarity_scores(targets, options)
    |> Enum.with_index()
    |> Enum.zip(targets)
    |> Enum.map(fn {{score, index}, value} ->
      %Match{value: value, score: score, index: index}
    end)
    |> Enum.sort_by(&{-&1.score, &1.index})
    |> Enum.take(limit)
  end

  defp validate_targets!(query, targets, options) do
    if length(targets) > options.max_batch_size do
      raise ArgumentError,
            "targets exceeds :max_batch_size (#{options.max_batch_size})"
    end

    total_bytes =
      targets
      |> Enum.with_index()
      |> Enum.reduce(byte_size(query), fn
        {target, index}, total when is_binary(target) ->
          validate_input!(target, options, "target #{index}")
          total + byte_size(target)

        {_target, index}, _total ->
          raise ArgumentError, "target #{index} must be a binary"
      end)

    if total_bytes > options.max_total_bytes do
      raise ArgumentError,
            "query and targets exceed :max_total_bytes (#{options.max_total_bytes})"
    end
  end

  defp validate_input!(input, options, label) do
    if byte_size(input) > options.max_bytes do
      raise ArgumentError,
            "#{label} exceeds :max_bytes (#{options.max_bytes})"
    end

    input
  end

  defp unwrap_native!({:ok, value}), do: value

  defp unwrap_native!({:error, :too_many_tokens}) do
    raise ArgumentError, "normalised input exceeds :max_tokens"
  end

  defp unwrap_native!({:error, :input_too_large}) do
    raise ArgumentError, "normalised input exceeds :max_bytes"
  end

  defp unwrap_native!({:error, :internal_error}) do
    raise RuntimeError, "Fuzler native scorer failed unexpectedly"
  end
end
