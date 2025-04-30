defmodule Fuzler.MixProject do
  use Mix.Project

  @version "0.1.0"

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

  def application do
    [
      extra_applications: []
    ]
  end

  defp description() do
    "Fuzler is a lightweight, reusable cache built on top of an ETS table and wrapped in a `GenServer`, with built-in fuzzy text search powered by a Rust NIF for high-performance similarity scoring."
  end

  defp package() do
    [
      name: "fuzler",
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
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
      {:benchee, "~> 1.0", only: :dev},
      # Documentation Provider
      {:ex_doc, "~> 0.28.3", only: [:dev, :test], optional: true, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
