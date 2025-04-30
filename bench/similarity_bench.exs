inputs = %{
  "tiny - identical"   => {"aaa",     "aaa"},
  "tiny - off by one"  => {"aaa",     "aab"},
  "small - fuzzy"      => {"cia",     "ciao bella"},
  "medium - sentence"  => {
    "elixirbench",
    "benchmarking example elixirbench"
  },
  "large - random(1K)" => {
     :crypto.strong_rand_bytes(512) |> Base.encode16(),
     :crypto.strong_rand_bytes(512) |> Base.encode16()
  }
}

Benchee.run(
  %{
    "NIF: nif_similarity_score/2"        => fn {q, t} -> Fuzler.nif_similarity_score(q, t) end,
    "Elixir: String.jaro_distance/2"     => fn {q, t} -> String.jaro_distance(q, t) end
  },
  inputs: inputs,
  warmup: 2,    # seconds per scenario warming up
  time:   5    # seconds measuring each scenario
)
