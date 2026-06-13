pub(crate) struct PasswordGenOptions {
    pub(crate) length: u8,
    pub(crate) uppercase: bool,
    pub(crate) lowercase: bool,
    pub(crate) numbers: bool,
    pub(crate) symbols: bool,
    pub(crate) exclude_ambiguous: bool,
}

const UPPERCASE: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const LOWERCASE: &[u8] = b"abcdefghijklmnopqrstuvwxyz";
const NUMBERS: &[u8] = b"0123456789";
const SYMBOLS: &[u8] = b"!@#$%^&*()-_=+[]{};:,.?/";
const AMBIGUOUS: &[u8] = b"0O1lI";
const WORDS: &[&str] = &[
    "amber", "anchor", "apple", "artist", "baker", "beacon", "breeze", "bridge", "cable", "cactus",
    "candle", "canvas", "castle", "cedar", "circle", "cloud", "copper", "coral", "cotton", "dawn",
    "delta", "desert", "ember", "falcon", "forest", "garden", "harbor", "hazel", "island",
    "jacket", "juniper", "kitten", "ladder", "lantern", "marble", "meadow", "mirror", "needle",
    "oasis", "orange", "parcel", "pepper", "planet", "pocket", "prairie", "quartz", "rabbit",
    "river", "rocket", "saddle", "silver", "spirit", "spring", "stable", "sunset", "timber",
    "tunnel", "velvet", "violet", "walnut", "window", "winter", "yellow", "zephyr",
];

pub(crate) fn generate_password(opts: PasswordGenOptions) -> Result<String, String> {
    if !(8..=64).contains(&opts.length) {
        return Err("length must be between 8 and 64".into());
    }

    let sets = enabled_sets(&opts)?;
    if (opts.length as usize) < sets.len() {
        return Err("length is too short for enabled character sets".into());
    }

    let mut bytes = Vec::with_capacity(opts.length as usize);
    for set in &sets {
        bytes.push(pick(set)?);
    }

    let all = sets.concat();
    while bytes.len() < opts.length as usize {
        bytes.push(pick(&all)?);
    }
    shuffle(&mut bytes)?;

    String::from_utf8(bytes).map_err(|_| "generated password is not UTF-8".into())
}

pub(crate) fn generate_passphrase(words: u8, sep: String) -> Result<String, String> {
    if !(4..=6).contains(&words) {
        return Err("words must be between 4 and 6".into());
    }

    let mut parts = Vec::with_capacity(words as usize);
    for _ in 0..words {
        parts.push(WORDS[pick_index(WORDS.len())?]);
    }
    Ok(parts.join(&sep))
}

fn enabled_sets(opts: &PasswordGenOptions) -> Result<Vec<Vec<u8>>, String> {
    let mut sets = Vec::new();
    if opts.uppercase {
        sets.push(filter_ambiguous(UPPERCASE, opts.exclude_ambiguous));
    }
    if opts.lowercase {
        sets.push(filter_ambiguous(LOWERCASE, opts.exclude_ambiguous));
    }
    if opts.numbers {
        sets.push(filter_ambiguous(NUMBERS, opts.exclude_ambiguous));
    }
    if opts.symbols {
        sets.push(filter_ambiguous(SYMBOLS, opts.exclude_ambiguous));
    }

    sets.retain(|s| !s.is_empty());
    if sets.is_empty() {
        return Err("at least one character set must be enabled".into());
    }
    Ok(sets)
}

fn filter_ambiguous(set: &[u8], exclude: bool) -> Vec<u8> {
    if !exclude {
        return set.to_vec();
    }
    set.iter()
        .copied()
        .filter(|b| !AMBIGUOUS.contains(b))
        .collect()
}

fn pick(set: &[u8]) -> Result<u8, String> {
    let index = pick_index(set.len())?;
    Ok(set[index])
}

fn pick_index(len: usize) -> Result<usize, String> {
    if len == 0 || len > 256 {
        return Err("random selection requires 1..=256 candidates".into());
    }

    let limit = 256 - (256 % len);
    loop {
        let mut b = [0u8; 1];
        getrandom::fill(&mut b).map_err(|_| "system random source failed".to_string())?;
        let value = b[0] as usize;
        if value < limit {
            return Ok(value % len);
        }
    }
}

fn shuffle(bytes: &mut [u8]) -> Result<(), String> {
    for i in (1..bytes.len()).rev() {
        let j = pick_index(i + 1)?;
        bytes.swap(i, j);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn default_options() -> PasswordGenOptions {
        PasswordGenOptions {
            length: 20,
            uppercase: true,
            lowercase: true,
            numbers: true,
            symbols: true,
            exclude_ambiguous: false,
        }
    }

    #[test]
    fn generated_password_respects_length_and_enabled_sets() {
        let password = generate_password(PasswordGenOptions {
            length: 32,
            uppercase: false,
            lowercase: true,
            numbers: true,
            symbols: false,
            exclude_ambiguous: false,
        })
        .unwrap();

        assert_eq!(password.chars().count(), 32);
        assert!(password
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit()));
    }

    #[test]
    fn generated_password_includes_each_enabled_set() {
        for _ in 0..1000 {
            let password = generate_password(default_options()).unwrap();
            assert!(
                password.chars().any(|c| c.is_ascii_uppercase()),
                "{password}"
            );
            assert!(
                password.chars().any(|c| c.is_ascii_lowercase()),
                "{password}"
            );
            assert!(password.chars().any(|c| c.is_ascii_digit()), "{password}");
            assert!(
                password
                    .chars()
                    .any(|c| "!@#$%^&*()-_=+[]{};:,.?/".contains(c)),
                "{password}"
            );
        }
    }

    #[test]
    fn generated_password_excludes_ambiguous_characters() {
        for _ in 0..1000 {
            let password = generate_password(PasswordGenOptions {
                exclude_ambiguous: true,
                ..default_options()
            })
            .unwrap();
            assert!(!password.chars().any(|c| "0O1lI".contains(c)), "{password}");
        }
    }

    #[test]
    fn generated_password_rejects_invalid_options() {
        assert!(generate_password(PasswordGenOptions {
            length: 7,
            ..default_options()
        })
        .unwrap_err()
        .contains("length"));

        assert!(generate_password(PasswordGenOptions {
            uppercase: false,
            lowercase: false,
            numbers: false,
            symbols: false,
            ..default_options()
        })
        .unwrap_err()
        .contains("character set"));
    }

    #[test]
    fn generated_passphrase_uses_requested_word_count_and_separator() {
        let phrase = generate_passphrase(5, "-".into()).unwrap();
        let words: Vec<_> = phrase.split('-').collect();

        assert_eq!(words.len(), 5);
        assert!(words
            .iter()
            .all(|w| w.chars().all(|c| c.is_ascii_lowercase())));
    }

    #[test]
    fn generated_passphrase_rejects_invalid_word_count() {
        assert!(generate_passphrase(3, "-".into())
            .unwrap_err()
            .contains("words"));
        assert!(generate_passphrase(7, "-".into())
            .unwrap_err()
            .contains("words"));
    }
}
