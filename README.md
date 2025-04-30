# Fuzler

`Fuzler` is a lightweight, reusable cache built on top of an ETS table and wrapped in a `GenServer`, with built‑in fuzzy text search powered by a Rust NIF for high-performance similarity scoring.

---

## Features

- **Named ETS table**: Give any atom as `:table`.
- **Public reads / protected writes**: ETS is `:public` with concurrency options; only the GenServer process can write.
- **O(1) lookup**: Table name → ETS table mapping stored in `:persistent_term`, avoiding extra GenServer calls.
- **Hot reload**: `reload/1` clears and repopulates from your loader function.
- **Insert / Get / Stream**: Standard cache operations.
- **Fuzzy full-text search**: `text_search/3` returns top‑N `{key, value, score}` suggestions using a SIMD‑accelerated Rust NIF.

---

## Installation

Add `fuzler` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:fuzler, git: "https://github.com/elchemista/fuzler.git"}
  ]
end
```

Then fetch and compile:

```bash
mix deps.get
mix compile
```

Make sure you have Rust installed; the Rustler NIF will compile automatically.

---

## Quickstart

### 1. Start the cache

```elixir
loader = fn ->
  [
    {"apple",  %{id: 1}},
    {"banana", %{id: 2}},
    {"cantaloupe", %{id: 3}}
  ]
end

{:ok, _pid} =
  Fuzler.start_link(
    table: :fruit_cache,
    loader: loader,
    name: :my_cache
  )
```

### 2. Basic operations

```elixir
# Get a value
Fuzler.get("banana")
#⇒ %{id: 2}

# Insert a new item
Fuzler.insert({"durian", %{id: 4}})
Fuzler.get("durian")
#⇒ %{id: 4}

# Reload all data
Fuzler.reload(:my_cache)

# Stream entries matching predicate
Fuzler.stream(fn %{id: id} -> id <= 2 end)
|> Enum.map(&elem(&1, 0))
#⇒ ["apple", "banana"]
```

### 3. Fuzzy text search

```elixir
# Suggest keys similar to "ap"
Fuzler.text_search("ap", limit: 5)
#⇒ [
#   {"apple", %{id: 1}, 1.0},
#   {"grape", %{id: 7}, 0.75},
#   ...
#]
```

- **Options**:
  - `:limit` – maximum results (default: 15)
  - `:threshold` – minimum score (default: 0.10)
  - `:keys` – pre-collected list of keys to search (avoids re-scanning ETS)

---

## Module API

```elixir
@spec start_link(opts :: keyword()) :: GenServer.on_start()
@spec reload(server \ server())        :: :ok
@spec insert({key, value}, server)     :: :ok
@spec get(key, server)                 :: value | nil
@spec stream((value -> boolean), server) :: Enumerable.t()
@spec text_search(String.t(), keyword(), server) :: [{key, value, float()}]
```

---

## Running tests

```bash
mix test    # runs Elixir tests
```

---

## License

MIT License
