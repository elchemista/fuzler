# bench/similarity_bench.exs
inputs = %{
  "tiny - identical"      => {"aaa", "aaa"},
  "tiny - off by one"     => {"aaa", "aab"},
  "small - fuzzy"         => {"cia", "ciao bella"},
  "medium - sentence"     => {
    "elixirbench",
    "benchmarking example elixirbench"
  },
  "large - random(1K)"    => {
    :crypto.strong_rand_bytes(512) |> Base.encode16(),
    :crypto.strong_rand_bytes(512) |> Base.encode16()
  },
  "xlarge - random(20K)"  => {
    :crypto.strong_rand_bytes(10_000) |> Base.encode16(),
    :crypto.strong_rand_bytes(10_000) |> Base.encode16()
  },
  "xxlarge - random(50K)" => {
    :crypto.strong_rand_bytes(25_000) |> Base.encode16(),
    :crypto.strong_rand_bytes(25_000) |> Base.encode16()
  },
  "huge - random(100K)"   => {
    :crypto.strong_rand_bytes(50_000) |> Base.encode16(),
    :crypto.strong_rand_bytes(50_000) |> Base.encode16()
  }
}

Benchee.run(
  %{
    "NIF: similarity_score/2"       => fn {q, t} -> Fuzler.similarity_score(q, t) end,
    "Elixir: String.jaro_distance/2" => fn {q, t} -> String.jaro_distance(q, t) end
  },
  inputs: inputs,
  warmup: 2,
  time: 5
)
