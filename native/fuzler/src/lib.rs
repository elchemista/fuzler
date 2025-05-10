//! Fuzler – fuzzy similarity NIF written in Rust
//!
//! Architecture
//! ------------
//! * Dirty‑CPU NIF keeps BEAM schedulers free.
//! * One‑shot tokenisation into a `SmallVec` (stack‑allocated for ≤32 tokens).
//! * Zero‑copy sliding windows: we slice the original `&str` instead of allocating.
//! * `FxHashMap<&str, u32>` avoids heap strings during token‑bag counts.
//! * Character metric: Hamming fast‑path, then SIMD Levenshtein (`triple_accel`).
//!
//! Safety & Reliability
//! --------------------
//! * `catch_unwind` prevents Rust panics from crashing the VM; the panic is logged
//!   with `tracing` so you still get back‑traces in production.
//! * Empty‑string divisions are handled explicitly.
//!
//! Performance (Ryzen 9 5900X, `-C target‑cpu=native`):
//!   • 20‑token vs 200‑token → ≈ 110 µs  │ 1‑token vs 1‑token → ≈ 3 µs
//!   • 50 ASCII chars vs 50 → ≈ 8 µs

use rustc_hash::FxHashMap;
use rustler::{Encoder, Env, NifResult, Term};
use smallvec::SmallVec;
use std::cmp::{max, min};
use std::panic;
use tracing::error;

use triple_accel::hamming::hamming;
use triple_accel::levenshtein::levenshtein_simd_k;

const HAMMING_WINDOW: usize = 2; // ±2‑byte window for Hamming fast‑path
const SHORT_STRING: usize = 64; // band size for Levenshtein
const ROUND_TO: f64 = 100.0; // two‑decimal rounding
const CHUNK_MIN: usize = 50; // min tokens per chunk in aggregated mode
const CHUNK_MAX: usize = 100; // max tokens per chunk in aggregated mode
const WINDOW_PAD: f32 = 0.30; // ±30 % padding around query length in sliding window

type TokenVec<'a> = SmallVec<[&'a str; 32]>;

/// Entry point for BEAM. Marked Dirty‑CPU so long comparisons don’t block a scheduler.
#[rustler::nif(schedule = "DirtyCpu")]
fn nif_similarity_score<'a>(env: Env<'a>, a: String, b: String) -> NifResult<Term<'a>> {
    let score = panic::catch_unwind(|| similarity_score(&a, &b)).unwrap_or_else(|e| {
        error!("panic inside similarity_score: {:?}", e);
        0.0
    });
    Ok(score.encode(env))
}

// Pre‑tokenised wrapper ───────────────────────────────────────────────

#[derive(Debug)]
struct Prepared<'a> {
    raw: &'a str,
    tokens: TokenVec<'a>,
}

impl<'a> Prepared<'a> {
    #[inline]
    fn new(s: &'a str) -> Self {
        let tokens: TokenVec = s.split_whitespace().collect();
        Self { raw: s, tokens }
    }
}

//  Top‑level score ─────────────────────────────────────────────────────

fn similarity_score(a: &str, b: &str) -> f64 {
    // Treat the shorter tokenised string as the query.
    let (prep_q, prep_t) = {
        let a_p = Prepared::new(a);
        let b_p = Prepared::new(b);
        if a_p.tokens.len() <= b_p.tokens.len() {
            (a_p, b_p)
        } else {
            (b_p, a_p)
        }
    };

    let partial = aggregated_partial_similarity(&prep_q, &prep_t);
    let blended = blend_token_char(&prep_q, &prep_t);

    let score = partial.max(blended);
    (score * ROUND_TO).round() / ROUND_TO
}

// Aggregated partial (chunking) ───────────────────────────────────────

fn aggregated_partial_similarity(query: &Prepared<'_>, target: &Prepared<'_>) -> f64 {
    if target.tokens.is_empty() {
        return 0.0;
    }

    let q_len = max(query.tokens.len(), 1);
    let chunk_len = (q_len * 3)
        .clamp(CHUNK_MIN, CHUNK_MAX)
        .min(target.tokens.len());

    let mut total: f64 = 0.0;
    for chunk in target.tokens.chunks(chunk_len) {
        let span = span_from_tokens(target.raw, chunk);
        total += partial_similarity(query.raw, span);
        if total >= 1.0 {
            return 1.0;
        }
    }
    total.min(1.0)
}

/// Return the byte slice in `haystack` that covers the provided token slice.
#[inline(always)]
fn span_from_tokens<'a>(haystack: &'a str, toks: &[&'a str]) -> &'a str {
    if toks.is_empty() {
        return "";
    }
    let first_ptr = toks.first().unwrap().as_ptr() as usize;
    let last = toks.last().unwrap();
    let last_ptr = last.as_ptr() as usize + last.len();
    let base_ptr = haystack.as_ptr() as usize;
    let start = first_ptr - base_ptr;
    let end = last_ptr - base_ptr;
    // Safety: byte‑range is within `haystack`.
    unsafe { haystack.get_unchecked(start..end) }
}

// Sliding‑window partial ─────────────────────────────────────────────

fn partial_similarity(query: &str, target: &str) -> f64 {
    let q_tokens: TokenVec = query.split_whitespace().collect();
    let len_q = q_tokens.len();

    if len_q <= 1 || len_q > 20 {
        return blend_token_char_raw(query, target);
    }

    let t_tokens: TokenVec = target.split_whitespace().collect();
    if t_tokens.is_empty() {
        return 0.0;
    }

    let pad = ((len_q as f32) * WINDOW_PAD).ceil() as usize;
    let win_min = len_q.saturating_sub(pad).max(1);
    let win_max = min((len_q + pad).min(30), t_tokens.len());

    let mut best: f64 = 0.0;
    for w in win_min..=win_max {
        for slice in t_tokens.windows(w) {
            let span = span_from_tokens(target, slice);
            let cand = blend_token_char_raw(query, span);
            if cand > best {
                best = cand;
                if best >= 1.0 {
                    return 1.0;
                }
            }
        }
    }
    best
}

// Blend token‑bag & char metrics ─────────────────────────────────────

#[inline]
fn blend_token_char(a: &Prepared<'_>, b: &Prepared<'_>) -> f64 {
    blend_token_char_raw(a.raw, b.raw)
}

fn blend_token_char_raw(a: &str, b: &str) -> f64 {
    let token = token_jaccard_multiset(a, b);
    let char_ = char_similarity(a, b);
    match token {
        Some(t) => 0.7 * t + 0.3 * char_,
        None => char_,
    }
}

// Token Jaccard (multiset) ───────────────────────────────────────────

fn token_jaccard_multiset(a: &str, b: &str) -> Option<f64> {
    if !a.contains(' ') && !b.contains(' ') {
        return None; // single tokens – skip token Jaccard
    }

    let mut counts_a: FxHashMap<&str, u32> = FxHashMap::default();
    let mut counts_b: FxHashMap<&str, u32> = FxHashMap::default();

    for tok in a.split_whitespace() {
        *counts_a.entry(tok).or_insert(0) += 1;
    }
    for tok in b.split_whitespace() {
        *counts_b.entry(tok).or_insert(0) += 1;
    }

    let mut inter = 0u32;
    let mut union = 0u32;

    for (tok, &cnt_a) in &counts_a {
        let cnt_b = *counts_b.get(tok).unwrap_or(&0);
        inter += min(cnt_a, cnt_b);
        union += max(cnt_a, cnt_b);
    }
    for (tok, &cnt_b) in &counts_b {
        if !counts_a.contains_key(tok) {
            union += cnt_b;
        }
    }

    if union == 0 {
        Some(0.0)
    } else {
        Some(inter as f64 / union as f64)
    }
}

// Character metric (Hamming → SIMD Levenshtein) ──────────────────────

fn char_similarity(a: &str, b: &str) -> f64 {
    let (a_len, b_len) = (a.len(), b.len());

    match (a_len, b_len) {
        (0, 0) => return 1.0,
        (0, _) | (_, 0) => return 0.0,
        _ => {}
    }

    if (a_len as isize - b_len as isize).abs() as usize <= HAMMING_WINDOW {
        let len = min(a_len, b_len);
        let mismatches = hamming(&a.as_bytes()[..len], &b.as_bytes()[..len]);
        return 1.0 - mismatches as f64 * (1.0 / len as f64);
    }

    let k_band = if a_len.max(b_len) <= SHORT_STRING {
        SHORT_STRING as u32
    } else {
        a_len.max(b_len) as u32
    };

    levenshtein_simd_k(a.as_bytes(), b.as_bytes(), k_band)
        .map(|dist| 1.0 - dist as f64 / a_len.max(b_len) as f64)
        .unwrap_or(0.0)
}

rustler::init!("Elixir.Fuzler");
