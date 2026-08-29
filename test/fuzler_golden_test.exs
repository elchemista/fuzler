defmodule FuzlerGoldenTest do
  use ExUnit.Case, async: true

  @threshold 0.5
  @fixture Path.expand("fixtures/golden_pairs.psv", __DIR__)

  @golden_pairs @fixture
                |> File.stream!()
                |> Stream.drop(1)
                |> Enum.map(fn line ->
                  [label, relevant, left, right, minimum, maximum] =
                    line |> String.trim_trailing() |> String.split("|")

                  %{
                    label: label,
                    relevant?: relevant == "true",
                    left: left,
                    right: right,
                    minimum: String.to_float(minimum),
                    maximum: String.to_float(maximum)
                  }
                end)

  test "golden scores stay inside their reviewed intervals" do
    for example <- @golden_pairs do
      score = Fuzler.similarity_score(example.left, example.right)

      assert score >= example.minimum and score <= example.maximum,
             "#{example.label}: expected #{example.minimum}..#{example.maximum}, got #{score}"
    end
  end

  test "the reviewed threshold retains perfect precision and recall" do
    predictions =
      Enum.map(@golden_pairs, fn example ->
        predicted? = Fuzler.similarity_score(example.left, example.right) >= @threshold
        {predicted?, example.relevant?}
      end)

    true_positives = Enum.count(predictions, &match?({true, true}, &1))
    false_positives = Enum.count(predictions, &match?({true, false}, &1))
    false_negatives = Enum.count(predictions, &match?({false, true}, &1))

    precision = true_positives / (true_positives + false_positives)
    recall = true_positives / (true_positives + false_negatives)

    assert precision == 1.0
    assert recall == 1.0
  end

  test "representative result rankings remain stable" do
    scenarios = [
      {"milano", ["Milano", "milanoo", "Milano Centrale", "Roma", "quantum physics"]},
      {"kitten", ["kitten", "kittens", "sitten", "sitting", "banana"]},
      {"new york", ["New York", "New York City", "York", "new yrok", "Cape Town"]}
    ]

    for {query, expected_order} <- scenarios do
      shuffled = Enum.reverse(expected_order)
      actual_order = Fuzler.top_matches(query, shuffled, length(shuffled)) |> Enum.map(& &1.value)

      assert actual_order == expected_order
    end
  end
end
