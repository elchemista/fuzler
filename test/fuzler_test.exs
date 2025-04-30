defmodule FuzlerTest do
  use ExUnit.Case, async: true
  @table :fuz_test

  setup do
    loader = fn -> [{"ciao", 1}, {"hola", 2}, {"hello", 3}] end
    _pid = start_supervised!({Fuzler, table: @table, loader: loader})
    :ok
  end

  test "get/2 fetches values" do
    assert Fuzler.get("ciao") == 1
    assert Fuzler.get("missing") == nil
  end

  test "insert/2 stores new entries" do
    Fuzler.insert({"salut", 4})
    # give the cast time to land
    Process.sleep(20)
    assert Fuzler.get("salut") == 4
  end

  test "reload/1 wipes custom inserts and restores loader data" do
    Fuzler.insert({"tmp", 99})
    Process.sleep(20)
    assert Fuzler.get("tmp") == 99
    Fuzler.reload()
    assert Fuzler.get("tmp") == nil
    assert Fuzler.get("ciao") == 1
  end

  test "stream/2 filters with predicate" do
    keys =
      Fuzler.stream(fn v -> v > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    assert keys == ["hello", "hola"]
  end

  test "text_search/3 returns top matches in descending score (or is skipped)" do
    if :erlang.function_exported(Fuzler, :nif_similarity_score, 2) do
      results = Fuzler.text_search("c", limit: 2)

      # at least one result
      assert [{k1, _v1, s1} | _] = results
      assert k1 == "ciao"
      assert s1 >= 0.10

      # ensure scores are non-increasing
      scores = Enum.map(results, &elem(&1, 2))
      assert scores == Enum.sort(scores, :desc)
    else
      IO.puts("NIF not loaded: skipping similarity test")
    end
  end
end
