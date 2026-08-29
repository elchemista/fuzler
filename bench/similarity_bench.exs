sentence = "fuzler compares lexical similarity between deterministic text samples"

long_text =
  1..2_000
  |> Enum.map_join(" ", &"token#{rem(&1, 100)}")

inputs = %{
  "tiny / identical" => {"aaa", "aaa"},
  "tiny / substitution" => {"aaa", "aab"},
  "Unicode / canonical form" => {"café", "cafe\u0301"},
  "Unicode / grapheme edit" => {"👩‍💻 develops in Elixir", "👩‍🔬 develops in Elixir"},
  "sentence / contained phrase" => {"lexical similarity", sentence},
  "sentence / unrelated" => {"pizza margherita", sentence},
  "long / one edit" => {long_text, String.replace(long_text, "token50", "token51", global: false)}
}

Benchee.run(
  %{
    "Fuzler.similarity_score/2" => fn {query, target} ->
      Fuzler.similarity_score(query, target)
    end,
    "String.jaro_distance/2" => fn {query, target} ->
      String.jaro_distance(query, target)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  reduction_time: 1,
  print: [fast_warning: false]
)
