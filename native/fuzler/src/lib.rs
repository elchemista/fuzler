use rustler::{Encoder, Env, NifResult, Term};
use std::cmp::min;
use std::collections::HashMap;
use std::panic;

use triple_accel::hamming::hamming;
use triple_accel::levenshtein::levenshtein_simd_k;

const HAMMING_WINDOW: usize = 2;
const SHORT_STRING: usize = 64; // band for Levenshtein
const ROUND_TO: f64 = 100.0; // two‑decimal rounding
const CHUNK_MIN: usize = 50; // min tokens per chunk
const CHUNK_MAX: usize = 100; // max tokens per chunk
const WINDOW_PAD: f32 = 0.30; // +/-30 % padding on window

// Public NIF
#[rustler::nif(schedule = "DirtyCpu")]
fn nif_similarity_score<'a>(env: Env<'a>, query: String, target: String) -> NifResult<Term<'a>> {
    // Catch any panic so the BEAM VM never crashes; fall back to 0.0
    let score = panic::catch_unwind(|| similarity_score(&query, &target)).unwrap_or(0.0);
    Ok(score.encode(env))
}

fn similarity_score(a: &str, b: &str) -> f64 {
    // always treat the shorter tokenised string as the query
    let (query, target) = if a.split_whitespace().count() <= b.split_whitespace().count() {
        (a, b)
    } else {
        (b, a)
    };

    // aggregated partial score (chunked target)
    let partial = aggregated_partial_similarity(query, target);

    // whole‑string token‑bag ⊕ char blend
    let blended = blend_token_char(a, b);

    // final score = max of the two paths, rounded
    let score = partial.max(blended);
    (score * ROUND_TO).round() / ROUND_TO
}

fn aggregated_partial_similarity(query: &str, target: &str) -> f64 {
    let target_tokens: Vec<&str> = target.split_whitespace().collect();
    if target_tokens.is_empty() {
        return 0.0;
    }

    let q_len = query.split_whitespace().count().max(1);
    let chunk_len = (q_len * 3)
        .clamp(CHUNK_MIN, CHUNK_MAX)
        .min(target_tokens.len());

    let mut total = 0.0;
    let mut idx = 0;
    while idx < target_tokens.len() {
        let end = (idx + chunk_len).min(target_tokens.len());
        let chunk = target_tokens[idx..end].join(" ");
        total += partial_similarity(query, &chunk);
        if total >= 1.0 {
            return 1.0;
        }
        idx = end;
    }
    total.min(1.0)
}

fn partial_similarity(query: &str, target: &str) -> f64 {
    let q_tokens: Vec<&str> = query.split_whitespace().collect();
    let len_q = q_tokens.len();

    // use whole‑string compare for trivial or very long queries
    if len_q <= 1 || len_q > 20 {
        return blend_token_char(query, target);
    }

    let t_tokens: Vec<&str> = target.split_whitespace().collect();
    if t_tokens.is_empty() {
        return 0.0;
    }

    let pad = (len_q as f32 * WINDOW_PAD).ceil() as usize;
    let win_min = len_q.saturating_sub(pad).max(1);
    let win_max = (len_q + pad).min(30);

    let mut best: f64 = 0.0;
    for w in win_min..=win_max {
        if w > t_tokens.len() {
            break;
        }
        for start in 0..=t_tokens.len() - w {
            let slice = &t_tokens[start..start + w].join(" ");
            best = best.max(blend_token_char(query, slice));
            if best == 1.0 {
                return 1.0;
            }
        }
    }

    best
}

fn blend_token_char(a: &str, b: &str) -> f64 {
    let token = token_jaccard_multiset(a, b);
    let char_ = char_similarity(a, b);
    match token {
        Some(t) => 0.7 * t + 0.3 * char_,
        None => char_,
    }
}

// token‑bag Jaccard over multisets (order‑agnostic)
fn token_jaccard_multiset(a: &str, b: &str) -> Option<f64> {
    if !a.contains(' ') && !b.contains(' ') {
        return None; // single tokens – skip
    }
    let counts_a = token_counts(a);
    let counts_b = token_counts(b);

    let mut inter = 0usize;
    let mut union = 0usize;

    for (tok, &cnt_a) in &counts_a {
        let cnt_b = counts_b.get(tok).copied().unwrap_or(0);
        inter += cnt_a.min(cnt_b);
        union += cnt_a.max(cnt_b);
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

fn token_counts(s: &str) -> HashMap<String, usize> {
    let mut map = HashMap::new();
    for tok in s.to_lowercase().split_whitespace() {
        *map.entry(tok.to_string()).or_insert(0) += 1;
    }
    map
}

// character‑level metric (Hamming -> SIMD Levenshtein)
fn char_similarity(a: &str, b: &str) -> f64 {
    let (a_len, b_len) = (a.len(), b.len());

    // Hamming fast‑path
    if (a_len as isize - b_len as isize).abs() as usize <= HAMMING_WINDOW {
        let len = min(a_len, b_len);
        let mismatches = hamming(&a.as_bytes()[..len], &b.as_bytes()[..len]);
        return 1.0 - mismatches as f64 / len as f64;
    }

    // SIMD Levenshtein (return 0.0 on unexpected None)
    let k_band = if a_len.max(b_len) <= SHORT_STRING {
        SHORT_STRING as u32
    } else {
        a_len.max(b_len) as u32
    };
    match levenshtein_simd_k(a.as_bytes(), b.as_bytes(), k_band) {
        Some(dist) => 1.0 - dist as f64 / a_len.max(b_len) as f64,
        None => 0.0,
    }
}

rustler::init!("Elixir.Fuzler");
