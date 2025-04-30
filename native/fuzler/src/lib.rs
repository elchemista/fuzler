use rustler::{Encoder, Env, NifResult, Term};
use std::cmp::min;
use triple_accel::hamming::hamming;
use triple_accel::levenshtein::levenshtein_simd_k; // ← root import

const HAMMING_WINDOW: usize = 2; // lengths considered “equal”

#[rustler::nif(schedule = "DirtyCpu")]
fn nif_similarity_score<'a>(env: Env<'a>, query: String, target: String) -> NifResult<Term<'a>> {
    Ok(similarity_score(&query, &target).encode(env))
}

fn similarity_score(query: &str, target: &str) -> f64 {
    let (q_bytes, t_bytes) = (query.as_bytes(), target.as_bytes());
    let (q_len, t_len) = (q_bytes.len(), t_bytes.len());

    // 1. Very fast Hamming when lengths differ ≤ 2
    if (q_len as isize - t_len as isize).abs() as usize <= HAMMING_WINDOW {
        let len = min(q_len, t_len);
        let mismatches = hamming(&q_bytes[..len], &t_bytes[..len]);
        return 1.0 - mismatches as f64 / len as f64;
    }

    // 2. Full SIMD Levenshtein – k = max len  → exact distance
    let k = q_len.max(t_len) as u32;
    let dist = levenshtein_simd_k(q_bytes, t_bytes, k).unwrap(); // always Some
    let score = ((1.0 - dist as f64 / k as f64) * 100.0).round() as f64 * 0.01;

    score
}

rustler::init!("Elixir.Fuzler");
