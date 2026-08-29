# Fuzler native engine

This crate implements the Rust NIF used by the Elixir `fuzler` package. It is
not published as an independent Rust API.

## Responsibilities

- Unicode NFC/NFKC normalisation and optional diacritic removal
- token-multiset Jaccard similarity
- ASCII SIMD Levenshtein and bounded grapheme-aware Unicode Levenshtein
- bounded partial-window matching
- resource-limit enforcement
- detailed and batch scoring NIFs

All exported NIFs use Rustler's dirty CPU scheduler. Panics are caught at the
NIF boundary and converted into an internal error for the Elixir wrapper.

## Development

Run native formatting, unit/property tests, and linting from the repository
root:

```console
cargo fmt --manifest-path native/fuzler/Cargo.toml --check
cargo test --manifest-path native/fuzler/Cargo.toml --locked --all-targets
cargo clippy --manifest-path native/fuzler/Cargo.toml --locked --all-targets --all-features -- -D warnings
```

The minimum supported Rust version is recorded in `Cargo.toml` and checked by
CI. Release archives are built by `.github/workflows/main.yml`.

## Fuzzing

Install `cargo-fuzz`, then run the target with a nightly toolchain:

```console
cd native/fuzler
cargo +nightly fuzz run similarity
```

The target checks arbitrary string pairs for panics, symmetry, determinism,
and score bounds without requiring a running BEAM VM.
