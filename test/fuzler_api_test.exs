defmodule FuzlerApiTest do
  use ExUnit.Case, async: true

  alias Fuzler.{Comparison, Match}

  describe "algorithm metadata and detailed comparisons" do
    test "exposes a stable algorithm version" do
      assert Fuzler.algorithm_version() == "1"
    end

    test "returns rounded component scores and the winning partial window" do
      assert %Comparison{
               score: 0.6,
               partial_score: 0.6,
               matched_text: "needle",
               algorithm_version: "1"
             } = Fuzler.compare("needle", "some text with needle inside")

      comparison = Fuzler.compare("bella ciao", "ciao bella")

      assert comparison.score == 0.7
      assert comparison.full_score == 0.7
      assert comparison.partial_score == 0.0
      assert comparison.token_score == 1.0
      assert comparison.character_score == 0.0
      assert comparison.matched_text == nil
    end

    test "single-token comparisons do not report a token component" do
      assert %Comparison{token_score: nil, character_score: 0.8} =
               Fuzler.compare("hello", "hallo")
    end
  end

  describe "Unicode options" do
    test "normalises canonical and compatibility-equivalent text" do
      assert Fuzler.similarity_score("café", "cafe\u0301") == 1.0
      assert Fuzler.similarity_score("ＦＵＺＬＥＲ", "fuzler") == 1.0
      assert Fuzler.similarity_score("ﬁle", "file") == 1.0
      assert Fuzler.similarity_score("𝐴", "a") == 1.0

      assert Fuzler.similarity_score("ﬁle", "file", normalization: :nfc) < 1.0
    end

    test "optionally removes diacritics" do
      assert Fuzler.similarity_score("café", "cafe") < 1.0
      assert Fuzler.similarity_score("café", "cafe", strip_diacritics: true) == 1.0
    end

    test "allows partial matching and component weights to be configured" do
      query = "needle"
      target = "some text with needle inside"

      assert Fuzler.similarity_score(query, target, partial: false) < 0.5

      assert Fuzler.similarity_score("bella ciao", "ciao bella", token_weight: 0.0) == 0.0
      assert Fuzler.similarity_score("bella ciao", "ciao bella", token_weight: 1) == 1.0

      assert Fuzler.similarity_score(query, target, partial_threshold: 1) == 0.6
    end
  end

  describe "batch and ranking APIs" do
    test "batch scoring is identical to repeated individual calls" do
      targets = ["Roma", "Milano", "Milano Centrale", "milano", "Torino"]

      expected = Enum.map(targets, &Fuzler.similarity_score("milano", &1))

      assert Fuzler.similarity_scores("milano", targets) == expected
      assert Fuzler.similarity_scores("milano", []) == []
    end

    test "top matches are stable for equal scores and retain source indexes" do
      targets = ["MILANO", "Roma", "milano", "Milano Centrale"]

      assert [
               %Match{value: "MILANO", score: 1.0, index: 0},
               %Match{value: "milano", score: 1.0, index: 2},
               %Match{value: "Milano Centrale", score: 0.75, index: 3}
             ] = Fuzler.top_matches("milano", targets, 3)

      assert Fuzler.top_matches("milano", targets, 0) == []
    end

    test "options are applied to every batch target" do
      assert Fuzler.similarity_scores("cafe", ["café", "cafe"], strip_diacritics: true) ==
               [1.0, 1.0]
    end
  end

  describe "resource limits and validation" do
    test "rejects input beyond the byte limit before entering the NIF" do
      assert_raise ArgumentError, ~r/query exceeds :max_bytes/, fn ->
        Fuzler.similarity_score("four", "ok", max_bytes: 3)
      end

      assert_raise ArgumentError, ~r/target exceeds :max_bytes/, fn ->
        Fuzler.similarity_score("ok", "four", max_bytes: 3)
      end

      assert_raise ArgumentError, ~r/target 1 exceeds :max_bytes/, fn ->
        Fuzler.similarity_scores("ok", ["ok", "four"], max_bytes: 3)
      end
    end

    test "rejects normalised expansion and excessive token counts in Rust" do
      assert_raise ArgumentError, ~r/normalised input exceeds :max_bytes/, fn ->
        Fuzler.similarity_score("½", "1", max_bytes: 2)
      end

      assert_raise ArgumentError, ~r/normalised input exceeds :max_tokens/, fn ->
        Fuzler.similarity_score("one-two", "one", max_tokens: 1)
      end
    end

    test "rejects oversized or malformed batches" do
      assert_raise ArgumentError, ~r/exceeds :max_batch_size/, fn ->
        Fuzler.similarity_scores("query", ["one", "two"], max_batch_size: 1)
      end

      assert_raise ArgumentError, ~r/exceed :max_total_bytes/, fn ->
        Fuzler.similarity_scores("aa", ["bb", "cc"], max_total_bytes: 5)
      end

      assert_raise ArgumentError, ~r/target 1 must be a binary/, fn ->
        Fuzler.similarity_scores("query", ["one", :two])
      end
    end

    test "rejects unknown options and invalid option values" do
      invalid_options = [
        [normalization: :none],
        [strip_diacritics: :yes],
        [partial: :yes],
        [token_weight: -0.1],
        [token_weight: 1.1],
        [partial_threshold: :high],
        [max_bytes: 0],
        [max_tokens: -1],
        [max_batch_size: 0],
        [max_total_bytes: 0],
        [unknown: true]
      ]

      for options <- invalid_options do
        assert_raise ArgumentError, fn -> Fuzler.similarity_score("a", "b", options) end
      end
    end

    test "non-binary and malformed UTF-8 values fail without crashing the VM" do
      invalid = Process.get(:fuzler_invalid_input, :invalid)
      invalid_limit = Process.get(:fuzler_invalid_limit, -1)

      assert_raise FunctionClauseError, fn -> Fuzler.compare(invalid, "valid") end
      assert_raise FunctionClauseError, fn -> Fuzler.similarity_scores(invalid, []) end
      assert_raise FunctionClauseError, fn -> Fuzler.top_matches("valid", [], invalid_limit) end
      assert_raise ArgumentError, fn -> Fuzler.compare(<<0xFF>>, "valid") end
    end
  end
end
