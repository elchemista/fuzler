defmodule Fuzler.BenchmarkRegression do
  @moduledoc false

  @samples 3
  @budgets_ms %{
    "batch_1000" => 250.0,
    "unicode_batch_500" => 500.0,
    "long_text" => 500.0
  }

  def run! do
    batch_targets =
      Enum.map(1..1_000, fn index ->
        "prefix #{rem(index, 20)} needle#{rem(index, 10)} suffix #{index}"
      end)

    unicode_targets =
      Enum.map(1..500, fn index ->
        "città numero #{index}: café 東京 👩‍💻"
      end)

    long_text = Enum.map_join(1..20_000, " ", &"token#{rem(&1, 500)}")
    edited_long_text = String.replace(long_text, "token250", "token251", global: false)

    checks = [
      {"batch_1000", fn -> Fuzler.similarity_scores("needle5", batch_targets) end},
      {"unicode_batch_500", fn -> Fuzler.similarity_scores("café 東京", unicode_targets) end},
      {"long_text", fn -> Fuzler.similarity_score(long_text, edited_long_text) end}
    ]

    Enum.each(checks, fn {name, operation} ->
      operation.()
      elapsed_ms = median_ms(operation)
      budget_ms = budget_ms(name)

      IO.puts("#{name}: #{Float.round(elapsed_ms, 2)} ms (budget #{budget_ms} ms)")

      if elapsed_ms > budget_ms do
        raise "benchmark regression for #{name}: #{elapsed_ms} ms exceeds #{budget_ms} ms"
      end
    end)
  end

  defp median_ms(operation) do
    durations =
      1..@samples
      |> Enum.map(fn _ ->
        started_at = System.monotonic_time()
        operation.()

        started_at
        |> then(&(System.monotonic_time() - &1))
        |> System.convert_time_unit(:native, :microsecond)
        |> Kernel./(1_000)
      end)
      |> Enum.sort()

    Enum.at(durations, div(@samples, 2))
  end

  defp budget_ms(name) do
    environment_name = "FUZLER_BENCH_#{String.upcase(name)}_MS"

    case System.get_env(environment_name) do
      nil -> Map.fetch!(@budgets_ms, name)
      value -> parse_budget!(environment_name, value)
    end
  end

  defp parse_budget!(environment_name, value) do
    case Float.parse(value) do
      {budget, ""} when budget > 0 -> budget
      _ -> raise "#{environment_name} must be a positive number"
    end
  end
end

Fuzler.BenchmarkRegression.run!()
