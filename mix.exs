defmodule Fuzler.MixProject do
  use Mix.Project

  @version "0.1.2"

  def project do
    [
      app: :fuzler,
      name: "Fuzler",
      version: @version,
      elixir: "~> 1.18",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "LICENSE"
        ]
      ],
      source_url: "https://github.com/elchemista/fuzler",
      homepage_url: "https://github.com/elchemista/fuzler"
    ]
  end

  defp description() do
    "A tiny, Rust‑powered string‑similarity helper for Elixir."
  end

  defp package() do
    [
      name: "fuzler",
      files: ~w(
             lib
             mix.exs
             README.md
             LICENSE
             checksum-Elixir.Fuzler.exs
             native/fuzler/Cargo.toml
             native/fuzler/src
             priv/native/*.so
      ),
      maintainers: ["Yuriy Zhar"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/elchemista/fuzler"}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:rustler, ">= 0.0.0", optional: true},
      {:rustler_precompiled, "~> 0.8"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.1", only: [:dev, :test], runtime: false},
      # Documentation Provider
      {:ex_doc, "~> 0.28.3", only: [:dev, :test], optional: true, runtime: false}
    ]
  end
end
