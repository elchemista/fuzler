# Fuzler

_A tiny, Rust‑powered string‑similarity helper for Elixir._

`Fuzler` gives you **one public function**:

```elixir
Fuzler.similarity_score(query :: String.t(), target :: String.t()) :: float
```

It returns a **normalised score in $0.0 – 1.0$** that tells you how closely
two pieces of text match—robust to typos, word‑order swaps, case and basic
punctuation.

Behind the scenes it calls a compiled Rust NIF that mixes:

- **Hamming distance** – for very short, nearly equal‑length strings.
- **SIMD Levenshtein** – fast edit distance from the `triple_accel` crate.
- **Token‑bag Jaccard** – ignores word order.
- **Partial‑ratio window** – finds the best‑matching snippet when the target is much longer than the query.

The result is symmetric (`score(a,b) ≈ score(b,a)`), length‑normalised and remains meaningful from single words to multi‑sentence paragraphs.

---

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:fuzler, "~> 0.1.2"}
  ]
end
```

You need **Rust ≥ 1.70** installed; `rustler` will compile the NIF automatically.

---

## Quick examples

```elixir
iex> Fuzler.similarity_score("ciao", "ciao")
1.0

iex> Fuzler.similarity_score("bella ciao", "ciao bella")
0.70       # same words, different order

iex> long_text = "bella ciao come va oggi spero che tu stia bene ..."
iex> Fuzler.similarity_score("ciao", long_text)
0.75       # query appears once inside a 40‑token paragraph

iex> Fuzler.similarity_score("bonjour", long_text)
0.12       # word not present
```

---

## When should I use it?

| Use case                                    | Why it works well                                    |
| ------------------------------------------- | ---------------------------------------------------- |
| typo‑tolerant autocomplete / “did‑you‑mean” | Hamming + Levenshtein catch small edits fast         |
| matching short queries inside long blobs    | windowed _partial ratio_ focuses on the best slice   |
| order‑agnostic key comparison               | token‑bag Jaccard treats “ciao bella” = “bella ciao” |
| quick relevance scoring in Elixir           | pure NIF call, no external service needed            |

**Not** a full‑text search engine or a semantic synonym matcher—that’s what
Tantivy / Embeddings are for.

---

## API

```elixir
@doc "Returns a similarity score ∈ [0.0, 1.0]"
@spec similarity_score(String.t(), String.t()) :: float
```

If the NIF failed to load you’ll get:

```elixir
:erlang.nif_error(:nif_not_loaded)
```

so your code can decide to fall back or skip tests.

---

## How good is the score?

| Query / Target                                      | Score ≈     |
| --------------------------------------------------- | ----------- |
| identical strings (any case / punctuation)          | 1.00        |
| same words, swapped order                           | 0.68 – 0.72 |
| one‑word query present once in 45‑token paragraph   | \~0.75      |
| one‑word query absent from paragraph                | ≤ 0.15      |
| 80‑token paragraph vs same with 1 typo              | ≥ 0.90      |
| “ciao bella” with +30 random filler tokens appended | \~0.58      |

---

## Running the test suite

`mix test` runs a handful of ExUnit cases covering:

- case & punctuation variations
- word‑order permutations
- query present / absent in long paragraph (> 40 tokens)
- very long strings with tiny edits
- monotonic drop as filler tokens grow

All similarity tests auto‑skip if the NIF isn’t loaded (e.g. on
CI without Rust).

---

## License

MIT [License](LICENSE)
