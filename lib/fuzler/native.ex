defmodule Fuzler.Native do
  @moduledoc false

  version = Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :fuzler,
    crate: "fuzler",
    base_url: "https://github.com/elchemista/fuzler/releases/download/v#{version}",
    force_build: System.get_env("RUSTLER_PRECOMPILATION_EXAMPLE_BUILD") in ["1", "true"],
    version: version

  @doc false
  def similarity_score(_query, _target, _options), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def compare(_query, _target, _options), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def similarity_scores(_query, _targets, _options), do: :erlang.nif_error(:nif_not_loaded)
end
