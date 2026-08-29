# Fuzler

[![CI](https://github.com/elchemista/fuzler/actions/workflows/ci.yml/badge.svg)](https://github.com/elchemista/fuzler/actions/workflows/ci.yml)
[![Fuzz](https://github.com/elchemista/fuzler/actions/workflows/fuzz.yml/badge.svg)](https://github.com/elchemista/fuzler/actions/workflows/fuzz.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/fuzler.svg)](https://hex.pm/packages/fuzler)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/fuzler)

Fuzler is a fast, configurable lexical similarity scorer for Elixir. Its Rust
NIF combines Unicode-aware edit distance, token overlap, and bounded partial
matching without blocking the BEAM's normal schedulers.

```elixir
Fuzler.similarity_score("kitten", "sitting")
#=> 0.57
```

Scores are symmetric, deterministic, rounded to two decimal places, and always
between `0.0` and `1.0`.

## Installation

Add Fuzler to `mix.exs`:

```elixir
def deps do
  [
    {:fuzler, "~> 0.1.3"}
  ]
end
```

Then run `mix deps.get`.

Fuzler requires Elixir 1.18 or later. Precompiled NIF archives are provided for:

- Linux: `aarch64` (GNU and musl), `arm-gnueabihf`, `riscv64gc-gnu`, and
  `x86_64` (GNU and musl)
- macOS: Apple Silicon and Intel
- Windows: `x86_64` GNU and MSVC

Building a development checkout or an unsupported target requires Rust 1.82 or
later. A consuming project that forces a source build must also include Rustler:

```elixir
def deps do
  [
    {:rustler, "~> 0.36.2"},
    {:fuzler, "~> 0.1.3"}
  ]
end
```

```console
RUSTLER_PRECOMPILATION_EXAMPLE_BUILD=1 mix compile --force
```

## Basic scoring

```elixir
iex> Fuzler.similarity_score("Hello, WORLD!", "hello world")
1.0

iex> Fuzler.similarity_score("bella ciao", "ciao bella")
0.7

iex> Fuzler.similarity_score("café", "cafe\u0301")
1.0

iex> Fuzler.similarity_score("needle", "some text with needle inside")
0.6
```

Useful reference points:

| Inputs | Score |
| --- | ---: |
| equivalent after normalisation | `1.0` |
| `"bella ciao"`, `"ciao bella"` | `0.7` |
| `"hello"`, `"hallo"` | `0.8` |
| `"kitten"`, `"sitting"` | `0.57` |
| `"a"`, `"ab"` | `0.5` |
| `""`, `""` | `1.0` |
| `""`, `"value"` | `0.0` |

Scores are ranking signals rather than universal thresholds. The reviewed
golden corpus currently has perfect precision and recall at `0.5`, but
applications should calibrate a threshold on their own representative data.

## Detailed comparisons

`compare/2` exposes the components that produced the final score:

```elixir
iex> Fuzler.compare("needle", "some text with needle inside")
%Fuzler.Comparison{
  score: 0.6,
  full_score: 0.2,
  partial_score: 0.6,
  token_score: 0.2,
  character_score: 0.21,
  matched_text: "needle",
  algorithm_version: "1"
}
```

`token_score` is `nil` for two single-token inputs. The token and character
components describe the full-input comparison; `matched_text` contains the
normalised target window only when partial matching wins.

## Batch scoring and ranking

Crossing the NIF boundary once is substantially cheaper than making many
individual calls. `similarity_scores/2` preserves input order:

```elixir
iex> Fuzler.similarity_scores("milano", ["Roma", "Milano", "Milano Centrale"])
[0.17, 1.0, 0.75]
```

`top_matches/3` returns ranked values and their zero-based source indexes:

```elixir
iex> Fuzler.top_matches("milano", ["Roma", "Milano", "Milano Centrale"], 2)
[
  %Fuzler.Match{value: "Milano", score: 1.0, index: 1},
  %Fuzler.Match{value: "Milano Centrale", score: 0.75, index: 2}
]
```

Equal scores retain input order.

## Options

All scoring, comparison, and batch functions accept an options argument. For
example:

```elixir
Fuzler.similarity_score("café", "cafe", strip_diacritics: true)
#=> 1.0

Fuzler.compare(query, target, partial: false, token_weight: 0.5)
Fuzler.similarity_scores(query, targets, max_batch_size: 500)
Fuzler.top_matches(query, targets, 10, normalization: :nfc)
```

| Option | Default | Meaning |
| --- | ---: | --- |
| `:normalization` | `:nfkc` | Unicode `:nfc` or compatibility `:nfkc` |
| `:strip_diacritics` | `false` | Treat accents as equivalent when enabled |
| `:partial` | `true` | Search candidate windows in longer text |
| `:token_weight` | `0.7` | Token contribution for multi-token comparisons |
| `:partial_threshold` | `0.6` | Reject weak partial candidates below this value |
| `:max_bytes` | `1_000_000` | Maximum bytes in each input |
| `:max_tokens` | `50_000` | Maximum normalised tokens in each input |
| `:max_batch_size` | `10_000` | Maximum targets in one batch |
| `:max_total_bytes` | `10_000_000` | Combined query and batch target bytes |

Unknown options and invalid values raise `ArgumentError`.

## Unicode and matching behaviour

By default Fuzler:

- lowercases Unicode text;
- applies NFKC compatibility normalisation;
- preserves accents while making composed and decomposed forms equivalent;
- turns punctuation and other separators into token boundaries;
- collapses repeated whitespace;
- compares non-ASCII text by Unicode grapheme clusters.

Consequently, `"foo-bar"` equals `"foo bar"`, `"café"` equals its decomposed
Unicode representation, and full-width `"ＦＵＺＬＥＲ"` equals `"fuzler"`.
Set `normalization: :nfc` to disable compatibility folding, or
`strip_diacritics: true` to make `"café"` and `"cafe"` equivalent.

Exact grapheme Levenshtein is bounded to 4,096 graphemes to prevent quadratic
work from monopolising a dirty scheduler. Larger Unicode comparisons fall back
to the SIMD byte path and remain subject to the configured input limits.

For multi-token text, the full score blends multiset Jaccard overlap with
character similarity. The default blend is 70% token overlap and 30% character
similarity. Repeated tokens are counted, while word order is ignored by the
token component.

When the shorter input has at most 20 tokens, partial matching searches bounded
windows in the longer input. Strong contained phrases receive a useful score,
but coverage penalties prevent a small phrase from becoming identical to an
entire document. Weak windows are discarded rather than accumulated.

`algorithm_version/0` returns `"1"`. Applications that persist scores can save
this value alongside them when future algorithm revisions need to coexist.

## Errors and resource safety

Inputs must be valid UTF-8 binaries. Non-binary arguments raise
`FunctionClauseError`; malformed UTF-8 and exceeded resource limits raise
`ArgumentError`. An unexpected native panic is caught at the NIF boundary and
reported as `RuntimeError` instead of crashing the VM.

Every NIF is scheduled as dirty CPU work. Batch size, per-input bytes,
normalised tokens, and total batch bytes are bounded by validated options.

Fuzler measures lexical similarity. It does not provide stemming, synonyms,
semantic embeddings, or full-text indexing.

## Development and quality

The complete local gate is available through [Task](https://taskfile.dev/):

```console
task test             # ExUnit, doctests, properties, and coverage
task rust-test        # Rust unit and property tests
task benchmark-check  # deterministic performance budgets
task package-smoke    # build and consume the Hex tar in isolation
task check            # complete non-fuzzing quality gate
task fuzz             # continuous libFuzzer session; stop with Ctrl-C
```

The behavioural suite contains 150 explicit name, city, phrase, structured,
typo, partial, and unrelated examples. A separate versioned golden set checks
reviewed score intervals, precision/recall, and candidate rankings. StreamData
and Proptest add hundreds of generated Unicode cases per run. CI also performs
a timed libFuzzer run.

The release workflow builds ten native targets, validates archive integrity and
version metadata, and generates `checksum-Elixir.Fuzler.Native.exs`. The package
smoke test extracts the exact Hex tar into an isolated consumer, compiles the
native source, loads the NIF, and calls the public API.

See [CHANGELOG.md](CHANGELOG.md) for the full release notes.

## License

Fuzler is released under the [MIT License](LICENSE).
