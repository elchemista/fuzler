defmodule FuzlerPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  property "arbitrary Unicode scores are symmetric, bounded, rounded, and deterministic" do
    check all(
            left <- StreamData.string(:utf8, max_length: 80),
            right <- StreamData.string(:utf8, max_length: 80),
            max_runs: 250
          ) do
      forward = Fuzler.similarity_score(left, right)
      reverse = Fuzler.similarity_score(right, left)

      assert forward == reverse
      assert forward >= 0.0 and forward <= 1.0
      assert forward == Float.round(forward, 2)
      assert forward == Fuzler.similarity_score(left, right)
    end
  end

  property "identity is one for arbitrary valid Unicode" do
    check all(value <- StreamData.string(:utf8, max_length: 120), max_runs: 250) do
      assert Fuzler.similarity_score(value, value) == 1.0
    end
  end

  property "batch scoring agrees with individual scoring" do
    check all(
            query <- StreamData.string(:utf8, max_length: 40),
            targets <-
              StreamData.list_of(StreamData.string(:utf8, max_length: 40), max_length: 20),
            max_runs: 150
          ) do
      expected = Enum.map(targets, &Fuzler.similarity_score(query, &1))

      assert Fuzler.similarity_scores(query, targets) == expected
    end
  end
end
