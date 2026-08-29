//! Native scoring engine for Fuzler.
//!
//! The public NIFs run on dirty CPU schedulers, enforce resource limits, and
//! catch unexpected Rust panics before they can cross the BEAM boundary.

use rustc_hash::FxHashMap;
use rustler::{Encoder, Env, Term};
use smallvec::SmallVec;
use std::cmp::min;
use std::panic;
use tracing::error;
use triple_accel::hamming::hamming;
use triple_accel::levenshtein::levenshtein_simd_k;
use unicode_normalization::{char::is_combining_mark, UnicodeNormalization};
use unicode_segmentation::UnicodeSegmentation;

const ALGORITHM_VERSION: &str = "1";
const SHORT_STRING: usize = 64;
const HAMMING_MAX_MISMATCHES: usize = 2;
const MAX_GRAPHEME_EDIT: usize = 4_096;
const ROUND_TO: f64 = 100.0;
const WINDOW_PAD: f32 = 0.30;

type TokenVec<'a> = SmallVec<[&'a str; 32]>;

rustler::atoms! {
    ok,
    error,
    input_too_large,
    too_many_tokens,
    internal_error
}

#[derive(Clone, Debug, rustler::NifMap)]
struct NativeOptions {
    normalization: String,
    strip_diacritics: bool,
    partial: bool,
    token_weight: f64,
    partial_threshold: f64,
    max_bytes: u64,
    max_tokens: u64,
}

impl Default for NativeOptions {
    fn default() -> Self {
        Self {
            normalization: "nfkc".to_owned(),
            strip_diacritics: false,
            partial: true,
            token_weight: 0.7,
            partial_threshold: 0.6,
            max_bytes: 1_000_000,
            max_tokens: 50_000,
        }
    }
}

#[derive(Debug, rustler::NifMap)]
struct ScoreBreakdown {
    score: f64,
    full_score: f64,
    partial_score: f64,
    token_score: Option<f64>,
    character_score: f64,
    matched_text: Option<String>,
    algorithm_version: String,
}

#[derive(Clone, Copy, Debug)]
enum LimitError {
    InputTooLarge,
    TooManyTokens,
}

impl LimitError {
    fn atom(self) -> rustler::Atom {
        match self {
            Self::InputTooLarge => input_too_large(),
            Self::TooManyTokens => too_many_tokens(),
        }
    }
}

#[derive(Debug)]
struct Prepared<'a> {
    raw: &'a str,
    tokens: TokenVec<'a>,
}

impl<'a> Prepared<'a> {
    #[inline]
    fn new(value: &'a str) -> Self {
        Self {
            raw: value,
            tokens: value.split_whitespace().collect(),
        }
    }
}

#[derive(Debug)]
struct Blend {
    score: f64,
    token: Option<f64>,
    character: f64,
}

#[derive(Debug)]
struct PartialMatch {
    score: f64,
    matched_text: Option<String>,
}

#[rustler::nif(name = "similarity_score", schedule = "DirtyCpu")]
fn nif_similarity_score<'a>(
    env: Env<'a>,
    query: String,
    target: String,
    options: NativeOptions,
) -> Term<'a> {
    encode_operation(env, || {
        compare_inputs(&query, &target, &options).map(|result| result.score)
    })
}

#[rustler::nif(name = "compare", schedule = "DirtyCpu")]
fn nif_compare<'a>(
    env: Env<'a>,
    query: String,
    target: String,
    options: NativeOptions,
) -> Term<'a> {
    encode_operation(env, || compare_inputs(&query, &target, &options))
}

#[rustler::nif(name = "similarity_scores", schedule = "DirtyCpu")]
fn nif_similarity_scores<'a>(
    env: Env<'a>,
    query: String,
    targets: Vec<String>,
    options: NativeOptions,
) -> Term<'a> {
    encode_operation(env, || {
        let normalized_query = prepare_input(&query, &options)?;

        targets
            .iter()
            .map(|target| {
                let normalized_target = prepare_input(target, &options)?;
                Ok(compare_normalized(&normalized_query, &normalized_target, &options).score)
            })
            .collect::<Result<Vec<_>, LimitError>>()
    })
}

fn encode_operation<'a, T, F>(env: Env<'a>, operation: F) -> Term<'a>
where
    T: Encoder,
    F: FnOnce() -> Result<T, LimitError>,
{
    match panic::catch_unwind(panic::AssertUnwindSafe(operation)) {
        Ok(Ok(value)) => (ok(), value).encode(env),
        Ok(Err(reason)) => (error(), reason.atom()).encode(env),
        Err(reason) => {
            error!("panic inside Fuzler native scorer: {:?}", reason);
            (error(), internal_error()).encode(env)
        }
    }
}

fn compare_inputs(
    left: &str,
    right: &str,
    options: &NativeOptions,
) -> Result<ScoreBreakdown, LimitError> {
    let normalized_left = prepare_input(left, options)?;
    let normalized_right = prepare_input(right, options)?;

    Ok(compare_normalized(
        &normalized_left,
        &normalized_right,
        options,
    ))
}

fn prepare_input(input: &str, options: &NativeOptions) -> Result<String, LimitError> {
    if input.len() as u64 > options.max_bytes {
        return Err(LimitError::InputTooLarge);
    }

    let normalized = normalize_with_options(input, options);

    if normalized.len() as u64 > options.max_bytes {
        return Err(LimitError::InputTooLarge);
    }

    if normalized.split_whitespace().count() as u64 > options.max_tokens {
        return Err(LimitError::TooManyTokens);
    }

    Ok(normalized)
}

fn compare_normalized(left: &str, right: &str, options: &NativeOptions) -> ScoreBreakdown {
    let left_prepared = Prepared::new(left);
    let right_prepared = Prepared::new(right);

    let (query, target) = if (
        left_prepared.tokens.len(),
        left_prepared.raw.len(),
        left_prepared.raw,
    ) <= (
        right_prepared.tokens.len(),
        right_prepared.raw.len(),
        right_prepared.raw,
    ) {
        (left_prepared, right_prepared)
    } else {
        (right_prepared, left_prepared)
    };

    let full = blend_token_character(query.raw, target.raw, options);
    let partial = partial_similarity(&query, &target, options);
    let score = partial.score.max(full.score).clamp(0.0, 1.0);
    let matched_text = if partial.score > full.score {
        partial.matched_text
    } else {
        None
    };

    ScoreBreakdown {
        score: round_score(score),
        full_score: round_score(full.score),
        partial_score: round_score(partial.score),
        token_score: full.token.map(round_score),
        character_score: round_score(full.character),
        matched_text,
        algorithm_version: ALGORITHM_VERSION.to_owned(),
    }
}

fn normalize_with_options(input: &str, options: &NativeOptions) -> String {
    let initial_normalization: String = match options.normalization.as_str() {
        "nfc" => input.nfc().collect(),
        _ => input.nfkc().collect(),
    };
    let lowercase: String = initial_normalization
        .chars()
        .flat_map(char::to_lowercase)
        .collect();
    let unicode_normalized: String = match options.normalization.as_str() {
        "nfc" => lowercase.nfc().collect(),
        _ => lowercase.nfkc().collect(),
    };

    let text = if options.strip_diacritics {
        unicode_normalized
            .nfd()
            .filter(|character| !is_combining_mark(*character))
            .nfc()
            .collect()
    } else {
        unicode_normalized
    };

    let mut normalized = String::with_capacity(text.len());
    let mut needs_separator = false;

    for character in text.chars() {
        if character.is_alphanumeric() {
            if needs_separator && !normalized.is_empty() {
                normalized.push(' ');
            }
            normalized.push(character);
            needs_separator = false;
        } else if is_combining_mark(character) && !normalized.is_empty() && !needs_separator {
            normalized.push(character);
        } else if !normalized.is_empty() {
            needs_separator = true;
        }
    }

    normalized
}

#[inline(always)]
fn span_from_tokens<'a>(haystack: &'a str, tokens: &[&'a str]) -> &'a str {
    if tokens.is_empty() {
        return "";
    }

    let first_pointer = tokens.first().unwrap().as_ptr() as usize;
    let last = tokens.last().unwrap();
    let last_pointer = last.as_ptr() as usize + last.len();
    let base_pointer = haystack.as_ptr() as usize;

    &haystack[(first_pointer - base_pointer)..(last_pointer - base_pointer)]
}

fn partial_similarity(
    query: &Prepared<'_>,
    target: &Prepared<'_>,
    options: &NativeOptions,
) -> PartialMatch {
    let query_length = query.tokens.len();
    let target_length = target.tokens.len();

    if !options.partial || query_length == 0 || query_length > 20 || query_length >= target_length {
        return PartialMatch {
            score: 0.0,
            matched_text: None,
        };
    }

    let padding = ((query_length as f32) * WINDOW_PAD).ceil() as usize;
    let minimum_window = query_length.saturating_sub(padding).max(1);
    let maximum_window = min((query_length + padding).min(30), target_length);
    let mut best_score = 0.0;
    let mut best_text = None;

    for window_length in minimum_window..=maximum_window {
        for window in target.tokens.windows(window_length) {
            let candidate_text = span_from_tokens(target.raw, window);
            let candidate = blend_token_character(query.raw, candidate_text, options);

            if candidate.score > best_score {
                best_score = candidate.score;
                best_text = Some(candidate_text.to_owned());
            }
        }
    }

    if best_score < options.partial_threshold {
        return PartialMatch {
            score: 0.0,
            matched_text: None,
        };
    }

    let coverage = query_length as f64 / target_length as f64;

    PartialMatch {
        score: best_score * (0.5 + 0.5 * coverage),
        matched_text: best_text,
    }
}

fn blend_token_character(left: &str, right: &str, options: &NativeOptions) -> Blend {
    let token = token_jaccard_multiset(left, right);
    let character = character_similarity(left, right);
    let score = match token {
        Some(token_score) => {
            options.token_weight * token_score + (1.0 - options.token_weight) * character
        }
        None => character,
    };

    Blend {
        score,
        token,
        character,
    }
}

fn token_jaccard_multiset(left: &str, right: &str) -> Option<f64> {
    if !left.contains(' ') && !right.contains(' ') {
        return None;
    }

    let mut left_counts: FxHashMap<&str, u32> = FxHashMap::default();
    let mut right_counts: FxHashMap<&str, u32> = FxHashMap::default();

    for token in left.split_whitespace() {
        *left_counts.entry(token).or_insert(0) += 1;
    }
    for token in right.split_whitespace() {
        *right_counts.entry(token).or_insert(0) += 1;
    }

    let mut intersection = 0_u32;
    let mut union = 0_u32;

    for (token, &left_count) in &left_counts {
        let right_count = *right_counts.get(token).unwrap_or(&0);
        intersection += min(left_count, right_count);
        union += left_count.max(right_count);
    }

    for (token, &right_count) in &right_counts {
        if !left_counts.contains_key(token) {
            union += right_count;
        }
    }

    if union == 0 {
        Some(0.0)
    } else {
        Some(intersection as f64 / union as f64)
    }
}

fn character_similarity(left: &str, right: &str) -> f64 {
    if left.is_ascii() && right.is_ascii() {
        return ascii_character_similarity(left, right);
    }

    let left_graphemes: Vec<&str> = left.graphemes(true).collect();
    let right_graphemes: Vec<&str> = right.graphemes(true).collect();

    match (left_graphemes.len(), right_graphemes.len()) {
        (0, 0) => return 1.0,
        (0, _) | (_, 0) => return 0.0,
        _ => {}
    }

    // Exact grapheme Levenshtein is quadratic. Keep it bounded for hostile or
    // unusually large Unicode inputs and use the SIMD byte path beyond that
    // point so a dirty scheduler cannot be monopolised indefinitely.
    if left_graphemes.len().max(right_graphemes.len()) > MAX_GRAPHEME_EDIT {
        return ascii_character_similarity(left, right);
    }

    if left_graphemes.len() == right_graphemes.len() {
        let mismatches = left_graphemes
            .iter()
            .zip(&right_graphemes)
            .filter(|(left_value, right_value)| left_value != right_value)
            .count();

        if mismatches <= HAMMING_MAX_MISMATCHES {
            return 1.0 - mismatches as f64 / left_graphemes.len() as f64;
        }
    }

    let distance = grapheme_levenshtein(&left_graphemes, &right_graphemes);
    1.0 - distance as f64 / left_graphemes.len().max(right_graphemes.len()) as f64
}

fn ascii_character_similarity(left: &str, right: &str) -> f64 {
    let (left_length, right_length) = (left.len(), right.len());

    match (left_length, right_length) {
        (0, 0) => return 1.0,
        (0, _) | (_, 0) => return 0.0,
        _ => {}
    }

    if left_length == right_length {
        let mismatches = hamming(left.as_bytes(), right.as_bytes()) as usize;
        if mismatches <= HAMMING_MAX_MISMATCHES {
            return 1.0 - mismatches as f64 / left_length as f64;
        }
    }

    let band = if left_length.max(right_length) <= SHORT_STRING {
        SHORT_STRING as u32
    } else {
        left_length.max(right_length) as u32
    };

    levenshtein_simd_k(left.as_bytes(), right.as_bytes(), band)
        .map(|distance| 1.0 - distance as f64 / left_length.max(right_length) as f64)
        .unwrap_or(0.0)
}

fn grapheme_levenshtein(left: &[&str], right: &[&str]) -> usize {
    let (rows, columns) = if left.len() >= right.len() {
        (left, right)
    } else {
        (right, left)
    };

    let mut previous: Vec<usize> = (0..=columns.len()).collect();
    let mut current = vec![0; columns.len() + 1];

    for (row_index, row_value) in rows.iter().enumerate() {
        current[0] = row_index + 1;

        for (column_index, column_value) in columns.iter().enumerate() {
            let substitution_cost = usize::from(row_value != column_value);
            current[column_index + 1] = min(
                min(current[column_index] + 1, previous[column_index + 1] + 1),
                previous[column_index] + substitution_cost,
            );
        }

        std::mem::swap(&mut previous, &mut current);
    }

    previous[columns.len()]
}

fn round_score(score: f64) -> f64 {
    (score * ROUND_TO).round() / ROUND_TO
}

/// Entry point used by the cargo-fuzz target without requiring a BEAM runtime.
#[doc(hidden)]
pub fn fuzz_similarity(left: &str, right: &str) -> f64 {
    compare_inputs(left, right, &NativeOptions::default())
        .map(|result| result.score)
        .unwrap_or(0.0)
}

rustler::init!("Elixir.Fuzler.Native");

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    fn calculate_similarity(left: &str, right: &str) -> f64 {
        compare_inputs(left, right, &NativeOptions::default())
            .unwrap()
            .score
    }

    fn normalize(input: &str) -> String {
        normalize_with_options(input, &NativeOptions::default())
    }

    fn assert_close(actual: f64, expected: f64) {
        assert!(
            (actual - expected).abs() <= 0.01,
            "expected {expected}, got {actual}"
        );
    }

    fn unicode_string() -> impl Strategy<Value = String> {
        proptest::collection::vec(any::<char>(), 0..96)
            .prop_map(|characters| characters.into_iter().collect())
    }

    #[test]
    fn normalizes_case_punctuation_whitespace_and_unicode_forms() {
        assert_eq!(normalize("  Ciao,\tBELLA!  "), "ciao bella");
        assert_eq!(normalize("CAFÉ"), "café");
        assert_eq!(normalize("cafe\u{301}"), "café");
        assert_eq!(normalize("ＦＵＺＬＥＲ"), "fuzler");
        assert_eq!(normalize("---"), "");
        assert_close(calculate_similarity("café", "cafe\u{301}"), 1.0);
    }

    #[test]
    fn optionally_strips_diacritics() {
        let options = NativeOptions {
            strip_diacritics: true,
            ..NativeOptions::default()
        };

        assert_eq!(
            normalize_with_options("Crème brûlée", &options),
            "creme brulee"
        );
        assert_eq!(compare_inputs("café", "cafe", &options).unwrap().score, 1.0);
    }

    #[test]
    fn handles_empty_and_unequal_length_strings() {
        assert_close(calculate_similarity("", ""), 1.0);
        assert_close(calculate_similarity("", "anything"), 0.0);
        assert!(calculate_similarity("a", "ab") < 1.0);
        assert_close(calculate_similarity("abc", "xabc"), 0.75);
        assert_close(calculate_similarity("xabc", "abcx"), 0.5);
    }

    #[test]
    fn uses_grapheme_edit_distance_for_non_ascii_text() {
        assert_close(character_similarity("café", "cafè"), 0.75);
        assert_close(character_similarity("東京", "京東"), 0.0);
        assert_close(character_similarity("👩‍💻", "👩‍🔬"), 0.0);
    }

    #[test]
    fn finds_exact_tokens_without_promoting_unrelated_text() {
        let target = "bella ciao come va oggi spero che tu stia bene mentre camminiamo insieme \
                      lungo la strada e parliamo dei sogni";

        assert!(calculate_similarity("ciao", target) >= 0.5);
        assert!(calculate_similarity("bonjour", target) <= 0.15);
    }

    #[test]
    fn does_not_sum_unrelated_chunk_scores() {
        let target = (0..200)
            .map(|index| format!("noise{index}"))
            .collect::<Vec<_>>()
            .join(" ");

        assert!(calculate_similarity("completely unrelated phrase", &target) < 0.5);
    }

    #[test]
    fn score_is_symmetric_and_bounded() {
        let cases = [
            ("bella ciao", "ciao bella"),
            ("one two", "zero one two three"),
            ("short", "a much longer piece of text"),
            ("CAFÉ!", "café"),
            ("東京", "東京都"),
            ("", "value"),
        ];

        for (left, right) in cases {
            let forward = calculate_similarity(left, right);
            let reverse = calculate_similarity(right, left);
            assert_eq!(forward, reverse, "asymmetric score for {left:?}, {right:?}");
            assert!((0.0..=1.0).contains(&forward));
        }
    }

    #[test]
    fn identity_and_normalisation_are_stable() {
        let samples = [
            "plain ASCII",
            "Punctuation, everywhere!",
            "caffè e tè",
            "cafe\u{301}",
            "tabs\tand\nnewlines",
            "東京と大阪",
            "",
        ];

        for sample in samples {
            assert_close(calculate_similarity(sample, sample), 1.0);
            let once = normalize(sample);
            assert_eq!(normalize(&once), once);
        }
    }

    #[test]
    fn repeated_tokens_use_multiset_similarity() {
        assert_close(token_jaccard_multiset("a a b", "a b b").unwrap(), 0.5);
        assert_close(token_jaccard_multiset("a b", "b a").unwrap(), 1.0);
    }

    #[test]
    fn edit_distance_paths_return_expected_scores() {
        assert_close(character_similarity("hello", "hallo"), 0.8);
        assert_close(character_similarity("kitten", "sitting"), 4.0 / 7.0);
        assert_close(character_similarity("xabc", "abcx"), 0.5);
    }

    #[test]
    fn partial_scores_decrease_with_target_coverage() {
        let base = "ciao bella";
        let targets = [
            "ciao bella",
            "ciao bella x1 x2",
            "ciao bella x1 x2 x3 x4 x5 x6",
            "ciao bella x1 x2 x3 x4 x5 x6 x7 x8 x9 x10",
        ];
        let scores: Vec<_> = targets
            .iter()
            .map(|target| calculate_similarity(base, target))
            .collect();

        assert!(scores.windows(2).all(|pair| pair[0] >= pair[1]));
        assert_eq!(scores[0], 1.0);
        assert!(scores.last().unwrap() < &0.6);
    }

    #[test]
    fn options_change_scoring_and_partial_matching() {
        let no_partial = NativeOptions {
            partial: false,
            ..NativeOptions::default()
        };
        let character_only = NativeOptions {
            token_weight: 0.0,
            ..NativeOptions::default()
        };

        let query = "needle";
        let target = "some text with needle inside";
        assert!(compare_inputs(query, target, &no_partial).unwrap().score < 0.5);
        assert!(
            compare_inputs("bella ciao", "ciao bella", &character_only)
                .unwrap()
                .score
                < 0.7
        );
    }

    #[test]
    fn detailed_score_identifies_the_partial_window() {
        let result = compare_inputs(
            "needle",
            "some text with needle inside",
            &NativeOptions::default(),
        )
        .unwrap();

        assert_eq!(result.score, 0.6);
        assert_eq!(result.matched_text.as_deref(), Some("needle"));
        assert_eq!(result.algorithm_version, ALGORITHM_VERSION);
    }

    #[test]
    fn enforces_byte_and_token_limits() {
        let byte_limited = NativeOptions {
            max_bytes: 3,
            ..NativeOptions::default()
        };
        let token_limited = NativeOptions {
            max_tokens: 2,
            ..NativeOptions::default()
        };

        assert!(matches!(
            compare_inputs("four", "ok", &byte_limited),
            Err(LimitError::InputTooLarge)
        ));
        assert!(matches!(
            compare_inputs("one two three", "ok", &token_limited),
            Err(LimitError::TooManyTokens)
        ));
    }

    #[test]
    fn token_spans_preserve_valid_utf8_boundaries() {
        let text = "uno\t caffè\ntre";
        let tokens: TokenVec = text.split_whitespace().collect();

        assert_eq!(span_from_tokens(text, &tokens[1..]), "caffè\ntre");
    }

    #[test]
    fn public_scores_are_rounded_to_two_decimals() {
        let cases = [
            ("kitten", "sitting"),
            ("hello", "hallo"),
            ("one two", "zero one two three"),
            ("caffè", "caffe"),
        ];

        for (left, right) in cases {
            let score = calculate_similarity(left, right);
            assert_close(score, (score * 100.0).round() / 100.0);
        }
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(256))]

        #[test]
        fn arbitrary_unicode_is_symmetric_and_bounded(left in unicode_string(), right in unicode_string()) {
            let forward = fuzz_similarity(&left, &right);
            let reverse = fuzz_similarity(&right, &left);

            prop_assert_eq!(forward, reverse);
            prop_assert!((0.0..=1.0).contains(&forward));
        }

        #[test]
        fn normalization_is_idempotent(value in unicode_string()) {
            let once = normalize(&value);
            prop_assert_eq!(normalize(&once), once);
        }

        #[test]
        fn identity_is_one_for_arbitrary_unicode(value in unicode_string()) {
            prop_assert_eq!(fuzz_similarity(&value, &value), 1.0);
        }
    }
}
