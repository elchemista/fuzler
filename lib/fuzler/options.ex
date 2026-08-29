defmodule Fuzler.Options do
  @moduledoc """
  Options accepted by Fuzler scoring functions.

  The defaults are:

    * `normalization: :nfkc` — Unicode compatibility normalisation;
    * `strip_diacritics: false` — preserve accents;
    * `partial: true` — search bounded windows in a longer target;
    * `token_weight: 0.7` — token contribution for multi-token text;
    * `partial_threshold: 0.6` — reject weak candidate windows;
    * `max_bytes: 1_000_000` — per-input resource limit;
    * `max_tokens: 50_000` — per-input normalised token limit;
    * `max_batch_size: 10_000` — maximum targets per batch call;
    * `max_total_bytes: 10_000_000` — combined query and batch target limit.

  Use `normalization: :nfc` when compatibility folding is undesirable. Set
  `strip_diacritics: true` to make values such as `"café"` and `"cafe"`
  equivalent.
  """

  @defaults [
    normalization: :nfkc,
    strip_diacritics: false,
    partial: true,
    token_weight: 0.7,
    partial_threshold: 0.6,
    max_bytes: 1_000_000,
    max_tokens: 50_000,
    max_batch_size: 10_000,
    max_total_bytes: 10_000_000
  ]

  @typedoc "Options controlling normalisation, scoring, and resource limits."
  @type option ::
          {:normalization, :nfc | :nfkc}
          | {:strip_diacritics, boolean()}
          | {:partial, boolean()}
          | {:token_weight, number()}
          | {:partial_threshold, number()}
          | {:max_bytes, pos_integer()}
          | {:max_tokens, pos_integer()}
          | {:max_batch_size, pos_integer()}
          | {:max_total_bytes, pos_integer()}

  @type validated :: %{
          normalization: :nfc | :nfkc,
          strip_diacritics: boolean(),
          partial: boolean(),
          token_weight: float(),
          partial_threshold: float(),
          max_bytes: pos_integer(),
          max_tokens: pos_integer(),
          max_batch_size: pos_integer(),
          max_total_bytes: pos_integer()
        }

  @doc false
  @spec validate!(keyword()) :: validated()
  def validate!(options) do
    options
    |> Keyword.validate!(@defaults)
    |> Map.new()
    |> validate_values!()
  end

  @doc false
  @spec to_native(validated()) :: map()
  def to_native(options) do
    options
    |> Map.take([
      :normalization,
      :strip_diacritics,
      :partial,
      :token_weight,
      :partial_threshold,
      :max_bytes,
      :max_tokens
    ])
    |> Map.update!(:normalization, &Atom.to_string/1)
  end

  defp validate_values!(options) do
    validate_member!(options, :normalization, [:nfc, :nfkc])
    validate_boolean!(options, :strip_diacritics)
    validate_boolean!(options, :partial)
    validate_probability!(options, :token_weight)
    validate_probability!(options, :partial_threshold)
    validate_positive!(options, :max_bytes)
    validate_positive!(options, :max_tokens)
    validate_positive!(options, :max_batch_size)
    validate_positive!(options, :max_total_bytes)

    options
    |> Map.update!(:token_weight, &(&1 * 1.0))
    |> Map.update!(:partial_threshold, &(&1 * 1.0))
  end

  defp validate_member!(options, key, allowed) do
    unless options[key] in allowed do
      raise ArgumentError, "#{inspect(key)} must be one of #{inspect(allowed)}"
    end
  end

  defp validate_boolean!(options, key) do
    unless is_boolean(options[key]) do
      raise ArgumentError, "#{inspect(key)} must be a boolean"
    end
  end

  defp validate_probability!(options, key) do
    value = options[key]

    unless is_number(value) and value >= 0 and value <= 1 do
      raise ArgumentError, "#{inspect(key)} must be a number between 0 and 1"
    end
  end

  defp validate_positive!(options, key) do
    unless is_integer(options[key]) and options[key] > 0 do
      raise ArgumentError, "#{inspect(key)} must be a positive integer"
    end
  end
end
