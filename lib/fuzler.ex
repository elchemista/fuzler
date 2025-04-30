defmodule Fuzler do
  use Rustler, otp_app: :fuzler, crate: "fuzler"

  @moduledoc """
  A lightweight, reusable cache built on an ETS table, wrapped in a `GenServer`.

  ## Highlights

  * **Named ETS** – give any atom as `:table`.
  * **Public reads / protected writes** – `:public`, `read_concurrency:` &
    `write_concurrency:` enabled; only the owner process mutates the table.
  * **O(1) table lookup** – mapping from server‐name → table stored in
    `:persistent_term`, avoiding a `GenServer.call/2` round‑trip for every
    public API invocation.
  * **Hot reload, insert, get, predicate stream** – as before.
  * **Fuzzy full‑text search on keys** – `text_search/3` uses
    `String.jaro_distance/2` (or any custom scorer) and thresholding.
  """

  use GenServer

  @enforce_keys [:table, :loader]
  defstruct [:table, :loader]

  alias Fuzler.TopHeap

  @type key :: term()
  @type value :: term()
  @opaque t :: %__MODULE__{table: atom(), loader: (-> Enumerable.t())}

  # Public API

  @doc """
  Starts the cache.

  Options:

    * `:table`  – **required** atom, the ETS table name.
    * `:loader` – **required** `() -> Enumerable.t()` that yields `{key, value}`.
    * `:ets_opts` – extra ETS options merged with sensible defaults
      `[:named_table, :public, read_concurrency: true, write_concurrency: true]`.
    * `:name` – process name (defaults to the module itself).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Reloads the cache by wiping the table and invoking the loader again.
  """
  @spec reload(GenServer.server()) :: :ok
  def reload(server \\ __MODULE__), do: GenServer.call(server, :reload)

  @doc """
  Inserts a `{key, value}` tuple into the cache.
  """
  @spec insert({key, value}, GenServer.server()) :: :ok
  def insert(tuple, server \\ __MODULE__), do: GenServer.cast(server, {:insert, tuple})

  @doc """
  Fetches `value` for `key`, or `nil` if not present.
  """
  @spec get(key, GenServer.server()) :: value | nil
  def get(key, server \\ __MODULE__) do
    case :ets.lookup(table_name(server), key) do
      [{^key, value}] -> value
      [] -> nil
    end
  end

  @doc """
  Returns a lazy stream of `{key, value}` pairs whose value satisfies
  `predicate.(value)`. When no predicate given, returns every entry.
  """
  @spec stream((value -> as_boolean(term)) | nil, GenServer.server()) :: Enumerable.t()
  def stream(predicate \\ fn _ -> true end, server \\ __MODULE__)
      when is_function(predicate, 1) do
    table = table_name(server)

    Stream.resource(
      fn -> :ets.first(table) end,
      fn
        :"$end_of_table" ->
          {:halt, nil}

        key ->
          [{^key, value}] = :ets.lookup(table, key)
          next = :ets.next(table, key)
          if predicate.(value), do: {[{key, value}], next}, else: {[], next}
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Fuzzy full‑text search on keys.

  * `query` – the search string.
  * `opts`  – `:threshold` (default `0.8`), `:limit` (default `:infinity`),
    `:scorer` (default `&String.jaro_distance/2`).

  Returns a list of `{key, value, score}` sorted by descending similarity.
  """
  def text_search(query, opts \\ [], server \\ __MODULE__)
      when is_binary(query) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 15)
    table = table_name(server)

    :ets.foldl(
      fn {k, v}, acc ->
        score = nif_similarity_score(query, to_string(k))

        if score < 0.10 do
          acc
        else
          # ← two-arity
          TopHeap.push_top({k, v, score}, acc)
        end
      end,
      TopHeap.new(limit),
      table
    )
    |> TopHeap.to_desc_list()
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    table = Keyword.fetch!(opts, :table)
    loader = Keyword.fetch!(opts, :loader)
    ets_opt = Keyword.get(opts, :ets_opts, [])
    name = Keyword.get(opts, :name, __MODULE__)

    :ets.new(
      table,
      [:named_table, :public, read_concurrency: true, write_concurrency: true] ++ ets_opt
    )

    load(loader, table)

    # O(1) lookup from server name/ PID → ETS table via persistent_term
    :persistent_term.put(pterm_key(name), table)

    {:ok, %__MODULE__{table: table, loader: loader}}
  end

  @impl true
  def handle_call(:reload, _from, %__MODULE__{table: table, loader: loader} = state) do
    :ets.delete_all_objects(table)
    load(loader, table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:table_name, _from, %__MODULE__{table: table} = state),
    do: {:reply, table, state}

  @impl true
  def handle_cast({:insert, {key, value}}, %__MODULE__{table: table} = state) do
    :ets.insert(table, {key, value})
    {:noreply, state}
  end

  # Helpers

  # Constant‑time ETS table lookup using persistent_term when possible.
  defp table_name(server) when is_atom(server) do
    case :persistent_term.get(pterm_key(server), :undefined) do
      :undefined -> GenServer.call(server, :table_name)
      table -> table
    end
  end

  defp table_name(server) when is_pid(server), do: GenServer.call(server, :table_name)

  defp pterm_key(name), do: {__MODULE__, name}

  defp load(loader, table) do
    loader.() |> Enum.each(fn {k, v} -> :ets.insert(table, {k, v}) end)
  end

  # NIF
  @spec nif_similarity_score(String.t(), String.t()) :: float()
  def nif_similarity_score(q, t), do: :erlang.nif_error(:nif_not_loaded)
end
