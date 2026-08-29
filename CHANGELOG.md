# Changelog

All notable changes to Fuzler are documented in this file. The project follows
[Semantic Versioning](https://semver.org/).

## 0.1.3 - 2026-08-29

### Added

- Add configurable `similarity_score/3`, detailed `compare/2`, native batch
  scoring, stable top-k ranking, and explicit algorithm versioning.
- Add NFC/NFKC normalisation, canonical Unicode equivalence, optional diacritic
  removal, and grapheme-aware edit distance.
- Add per-input, token, batch-size, and total-byte resource limits.
- Add a reviewed golden dataset with score intervals, precision/recall, and
  ranking expectations.
- Add StreamData and Proptest properties, a libFuzzer target and workflow,
  deterministic benchmarks with regression budgets, and an isolated Hex
  package smoke test.

### Changed

- Normalise case, punctuation, and repeated whitespace consistently before
  scoring.
- Run the native comparison on a dirty CPU scheduler.
- Keep token matching symmetric and account for repeated tokens as a multiset.
- Penalise partial matches according to their coverage of the longer input.
- Move native loading behind a private module while keeping the public
  `Fuzler.similarity_score/2` API unchanged.
- Expand HexDocs and package metadata, and add reproducible CI and release
  workflows.
- Require Rust 1.82 for source builds and verify it in CI.

### Fixed

- Do not use Hamming distance for unequal-length inputs; values such as `"a"`
  and `"ab"` can no longer be reported as identical.
- Do not combine weak matches found in unrelated parts of a target.
- Keep UTF-8 token-window slicing on valid byte boundaries.
- Catch unexpected Rust panics without building the release NIF with
  `panic = "abort"`.
- Make a missing NIF fail the test suite instead of silently bypassing all
  assertions.

### Quality

- Add ExUnit doctests, a 150-example behavioural corpus, generated properties,
  invariant and concurrency coverage, malformed-input cases, and native Rust
  tests.
- Enforce more than 90% Elixir coverage and warnings-as-errors in CI.
- Run strict Credo, Dialyzer, Hex dependency audit, HexDocs verification,
  package validation, Rust formatting, tests, and Clippy in CI.

## 0.1.2 - 2025-05-10

- Published precompiled native archives and checksums for Hex installation.

## 0.1.1 - 2025-05-04

- Prerelease of the RustlerPrecompiled packaging flow.

## 0.1.0 - 2025-04-30

- Initial release.

[0.1.2]: https://github.com/elchemista/fuzler/releases/tag/v0.1.2
[0.1.1]: https://github.com/elchemista/fuzler/releases/tag/v0.1.1
[0.1.0]: https://github.com/elchemista/fuzler/releases/tag/v0.1.0
