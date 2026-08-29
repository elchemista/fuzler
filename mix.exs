defmodule Fuzler.MixProject do
  use Mix.Project

  @version "0.1.3"

  def project do
    [
      app: :fuzler,
      name: "Fuzler",
      version: @version,
      elixir: "~> 1.18",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      test_coverage: [
        summary: [threshold: 95],
        ignore_modules: [Fuzler.Native]
      ],
      deps: deps(),
      description: description(),
      package: package(),
      rustler_precompiled: [
        provider: :github,
        owner: "elchemista",
        repo: "fuzler",
        tag: "v#{@version}"
      ],
      docs: [
        main: "readme",
        source_ref: "v#{@version}",
        extras: [
          "README.md",
          "CHANGELOG.md",
          "LICENSE"
        ]
      ],
      source_url: "https://github.com/elchemista/fuzler",
      homepage_url: "https://github.com/elchemista/fuzler"
    ]
  end

  defp description() do
    "Unicode-aware lexical similarity for Elixir with explainable, batch-ready Rust NIF scoring."
  end

  defp package() do
    [
      name: "fuzler",
      files: ~w(
             lib
             mix.exs
             README.md
             CHANGELOG.md
             LICENSE
             checksum-*.exs
             native/fuzler/Cargo.toml
             native/fuzler/Cargo.lock
             native/fuzler/README.md
             native/fuzler/src
      ),
      maintainers: ["Yuriy Zhar"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/elchemista/fuzler"}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:rustler, "~> 0.36.2", optional: true},
      {:rustler_precompiled, "~> 0.8.4"},
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.4", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.4", only: :test},
      # Documentation Provider
      {:ex_doc, "~> 0.40.3", only: [:dev, :test], optional: true, runtime: false}
    ]
  end
end
