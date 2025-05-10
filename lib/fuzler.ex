defmodule Fuzler do
  # use Rustler, otp_app: :fuzler, crate: "fuzler"

  version = Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :fuzler,
    crate: "fuzler",
    base_url: "https://github.com/elchemista/fuzler/releases/download/v#{version}",
    force_build: System.get_env("RUSTLER_PRECOMPILATION_EXAMPLE_BUILD") in ["1", "true"],
    version: version

  @doc """
  Returns a similarity score between `query` and `target`.
  """

  @spec similarity_score(String.t(), String.t()) :: float()
  def similarity_score(query, target) when is_binary(query) and is_binary(target),
    do: nif_similarity_score(query, target)

  # NIF
  @spec nif_similarity_score(String.t(), String.t()) :: float()
  defp nif_similarity_score(_q, _t), do: :erlang.nif_error(:nif_not_loaded)
end
