#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: (String, String)| {
    let (left, right) = data;
    let forward = fuzler::fuzz_similarity(&left, &right);
    let reverse = fuzler::fuzz_similarity(&right, &left);

    assert_eq!(forward, reverse);
    assert!((0.0..=1.0).contains(&forward));
    assert_eq!(forward, fuzler::fuzz_similarity(&left, &right));
});
