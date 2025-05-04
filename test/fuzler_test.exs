defmodule FuzlerTest do
  use ExUnit.Case, async: true

  @nif_loaded :erlang.function_exported(Fuzler, :nif_similarity_score, 2)

  # helper for a tolerant equality check
  defp assert_close(a, b, delta \\ 0.02) do
    assert_in_delta a, b, delta
  end

  @tag :similarity
  test "identical strings (case & punctuation variants) score ~1.0" do
    if @nif_loaded do
      assert_close(Fuzler.similarity_score("Hello world!", "Hello world!"), 1.0)
      assert_close(Fuzler.similarity_score("Hello world!", "hello world"), 1.0)
      assert_close(Fuzler.similarity_score("Ciao, bella.", "ciao bella"), 1.0)
    end
  end

  @tag :similarity
  test "order permutations yield similar score" do
    if @nif_loaded do
      s1 = Fuzler.similarity_score("bella ciao", "ciao bella")
      s2 = Fuzler.similarity_score("bella ciao", "bella ciao")
      assert_close(s1, s2)
    end
  end

  @tag :similarity
  test "one‑word query inside vs absent from long text" do
    if @nif_loaded do
      paragraph =
        Enum.join(
          ~w(bella ciao come va oggi spero che tu stia bene mentre camminiamo insieme lungo la
             strada e parliamo dei sogni che inseguiamo sotto il cielo azzurro d estate),
          " "
        )

      present_score = Fuzler.similarity_score("ciao", paragraph)
      absent_score = Fuzler.similarity_score("bonjour", paragraph)

      assert present_score >= 0.5
      assert absent_score <= 0.15
    end
  end

  @tag :similarity
  test "very long paragraphs with minor edit still score high" do
    if @nif_loaded do
      base =
        Enum.join(
          Enum.map(1..80, &"token#{&1}"),
          " "
        )

      edited = String.replace(base, "token40", "token40X")

      score = Fuzler.similarity_score(base, edited)
      assert score >= 0.9
    end
  end

  @tag :similarity
  test "similarity decreases as filler tokens are appended" do
    if @nif_loaded do
      base = "ciao bella"

      scores =
        for extra <- 0..4 do
          filler = Enum.map(1..(extra * 10), &"x#{&1}") |> Enum.join(" ")
          Fuzler.similarity_score(base, base <> " " <> filler)
        end

      assert Enum.sort(scores, :desc) == scores
      assert hd(scores) == 1.0
      assert List.last(scores) < 0.6
    end
  end
end
