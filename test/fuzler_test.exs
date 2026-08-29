defmodule FuzlerTest do
  use ExUnit.Case, async: true

  doctest Fuzler

  defp assert_score(left, right, expected, delta \\ 0.01) do
    assert_in_delta Fuzler.similarity_score(left, right), expected, delta
  end

  defp filler(0), do: ""
  defp filler(count), do: Enum.map_join(1..count, " ", &"x#{&1}")

  describe "normalisation" do
    test "ignores letter case, punctuation and repeated whitespace" do
      assert_score("Hello world!", "hello   WORLD", 1.0)
      assert_score("Ciao, bella.", "ciao bella", 1.0)
      assert_score("foo-bar", "foo bar", 1.0)
      assert_score("  CAFÉ\t", "café!!!", 1.0)
    end

    test "defines empty and punctuation-only inputs" do
      assert_score("", "", 1.0)
      assert_score("---", "!!!", 1.0)
      assert_score("", "value", 0.0)
    end
  end

  describe "full-string similarity" do
    test "scores common edit-distance examples" do
      assert_score("hello", "hallo", 0.8)
      assert_score("kitten", "sitting", 0.57)
      assert_score("abc", "xabc", 0.75)
      assert_score("xabc", "abcx", 0.5)
    end

    test "never treats unequal lengths as identical" do
      assert_score("a", "ab", 0.5)
      refute Fuzler.similarity_score("prefix", "prefix suffix") == 1.0
    end

    test "uses token multisets without depending on word order" do
      assert_score("bella ciao", "ciao bella", 0.7)
      assert Fuzler.similarity_score("one one two", "one two two") < 1.0
    end

    test "keeps long near-identical inputs close" do
      base = Enum.map_join(1..80, " ", &"token#{&1}")
      edited = String.replace(base, "token40", "token40X")

      assert Fuzler.similarity_score(base, edited) >= 0.9
    end
  end

  describe "partial matching" do
    test "finds a word inside a paragraph without promoting unrelated text" do
      paragraph =
        Enum.join(
          ~w(bella ciao come va oggi spero che tu stia bene mentre camminiamo insieme lungo la
             strada e parliamo dei sogni che inseguiamo sotto il cielo azzurro d estate),
          " "
        )

      assert Fuzler.similarity_score("ciao", paragraph) >= 0.5
      assert Fuzler.similarity_score("bonjour", paragraph) <= 0.15
    end

    test "penalises unrelated target growth monotonically" do
      base = "ciao bella"

      scores =
        for extra <- [0, 10, 20, 30, 40] do
          target = String.trim(base <> " " <> filler(extra))
          Fuzler.similarity_score(base, target)
        end

      assert scores == Enum.sort(scores, :desc)
      assert hd(scores) == 1.0
      assert List.last(scores) < 0.6
    end

    test "does not add weak matches from separate target regions" do
      target = Enum.map_join(1..200, " ", &"noise#{&1}")

      assert Fuzler.similarity_score("completely unrelated phrase", target) < 0.5
    end
  end

  describe "score invariants" do
    test "scores are symmetric, bounded and rounded to two decimals" do
      corpus = [
        "",
        "plain ASCII",
        "Punctuation, everywhere!",
        "caffè e tè",
        "one two",
        "zero one two three",
        "short",
        "a much longer piece of text"
      ]

      for left <- corpus, right <- corpus do
        forward = Fuzler.similarity_score(left, right)
        reverse = Fuzler.similarity_score(right, left)

        assert forward == reverse
        assert forward >= 0.0 and forward <= 1.0
        assert forward == Float.round(forward, 2)
      end
    end

    test "concurrent dirty-CPU NIF calls stay deterministic" do
      results =
        1..200
        |> Task.async_stream(
          fn index ->
            query = "needle#{rem(index, 10)}"
            target = "prefix words #{query} suffix words #{index}"

            {Fuzler.similarity_score(query, target), Fuzler.similarity_score(target, query)}
          end,
          max_concurrency: System.schedulers_online(),
          ordered: false,
          timeout: 10_000
        )
        |> Enum.to_list()

      assert Enum.all?(results, fn {:ok, {forward, reverse}} ->
               forward == reverse and forward >= 0.5 and forward <= 1.0
             end)
    end
  end

  describe "invalid inputs" do
    test "rejects non-binary arguments" do
      invalid = Process.get(:fuzler_invalid_input, :ciao)

      assert_raise FunctionClauseError, fn -> Fuzler.similarity_score(invalid, "ciao") end
      assert_raise FunctionClauseError, fn -> Fuzler.similarity_score("ciao", invalid) end
    end

    test "rejects malformed UTF-8 without crashing the VM" do
      assert_raise ArgumentError, fn -> Fuzler.similarity_score(<<0xFF>>, "valid") end
      assert_raise ArgumentError, fn -> Fuzler.similarity_score("valid", <<0xC3>>) end
    end
  end

  test "Elixir and Rust package versions stay in sync" do
    cargo_toml = File.read!(Path.expand("../native/fuzler/Cargo.toml", __DIR__))
    [_, cargo_version] = Regex.run(~r/^version = "([^"]+)"$/m, cargo_toml)

    assert cargo_version == Mix.Project.config()[:version]
    assert cargo_version == "0.1.3"
  end
end
