import Foundation

/// Rejects obvious passwords before they ever reach Supabase.
///
/// Follows NIST SP 800-63B: length is the only hard composition rule (8–64),
/// and everything else is a *blocklist* check rather than a "must contain a
/// symbol" rule. Forced character classes push people towards `Password1!`,
/// which a blocklist catches and a composition rule waves through — so the
/// checks here are guessability-shaped instead.
///
/// Runs entirely on device: no network call, nothing typed leaves the phone.
enum PasswordPolicy {

    /// NIST recommends a minimum of 8 and permitting at least 64. The upper
    /// bound also matches what GoTrue will accept in one bcrypt round.
    static let minimumLength = 8
    static let maximumLength = 64

    enum Strength: Int, Comparable {
        /// Fails a hard rule; cannot be used.
        case unacceptable
        case weak
        case fair
        case strong

        static func < (lhs: Strength, rhs: Strength) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var label: String {
            switch self {
            case .unacceptable: "Too weak"
            case .weak: "Weak"
            case .fair: "Fair"
            case .strong: "Strong"
            }
        }

        /// 0–1, for the meter width.
        var fraction: Double {
            switch self {
            case .unacceptable: 0.18
            case .weak: 0.42
            case .fair: 0.72
            case .strong: 1.0
            }
        }
    }

    struct Assessment: Equatable {
        let strength: Strength
        /// The single most useful thing to fix, or nil when there is nothing
        /// blocking. Shown verbatim under the field.
        let problem: String?

        var isAcceptable: Bool { strength > .unacceptable }
    }

    /// Judges `password`, using `email` for context so someone cannot use
    /// their own address as their password.
    static func assess(_ password: String, email: String? = nil) -> Assessment {
        if password.isEmpty {
            return Assessment(strength: .unacceptable, problem: nil)
        }
        if password.count < minimumLength {
            return .init(
                strength: .unacceptable,
                problem: "Use at least \(minimumLength) characters."
            )
        }
        if password.count > maximumLength {
            return .init(
                strength: .unacceptable,
                problem: "Keep it to \(maximumLength) characters or fewer."
            )
        }
        // Whitespace-only padding would pass the length check otherwise.
        if password.trimmingCharacters(in: .whitespaces).count < minimumLength {
            return .init(
                strength: .unacceptable,
                problem: "Use at least \(minimumLength) characters that aren't spaces."
            )
        }
        if let problem = hardFailure(password, email: email) {
            return .init(strength: .unacceptable, problem: problem)
        }
        return .init(strength: score(password), problem: nil)
    }

    // MARK: Blocklist checks

    /// The checks that disqualify a password outright, in the order that
    /// produces the most actionable message.
    private static func hardFailure(_ password: String, email: String?) -> String? {
        let lowered = password.lowercased()
        let variants = normalizations(of: lowered)
        let core = trimmingNonLetters(applyingLeet(lowered))

        if !commonPasswords.isDisjoint(with: variants) {
            return "That's one of the most common passwords. Pick something else."
        }
        if let email, containsIdentity(lowered, email: email) {
            return "Don't use your email address in your password."
        }
        if brandTerms.contains(where: { core.contains($0) && core.count <= $0.count + 4 }) {
            return "Don't build it around the app or company name."
        }
        if distinctCharacterCount(lowered) <= 3 {
            return "Too repetitive — mix in more different characters."
        }
        if isRun(lowered) {
            return "Sequences like that are guessed first. Try something less ordered."
        }
        if isKeyboardWalk(core) {
            return "That's a keyboard pattern. Try something less ordered."
        }
        if lowered.allSatisfy(\.isNumber) {
            return "Digits alone are easy to guess. Add letters."
        }
        return nil
    }

    /// Every way a decorated password might collapse back to a blocklisted
    /// one, so `P@ssw0rd2024!` and `letmein1` are both caught.
    ///
    /// Both orderings are needed: substituting first turns `2024` into `2o2a`,
    /// which then blocks the trailing-padding strip — so trim-then-substitute
    /// has to be in the set too.
    private static func normalizations(of lowered: String) -> Set<String> {
        let substituted = applyingLeet(lowered)
        let trimmed = trimmingNonLetters(lowered)
        return [
            lowered,
            trimmed,
            substituted,
            trimmingNonLetters(substituted),
            applyingLeet(trimmed),
        ]
    }

    /// Undoes the usual character swaps: `p@ssw0rd` → `password`.
    private static func applyingLeet(_ input: String) -> String {
        let substitutions: [Character: Character] = [
            "@": "a", "4": "a", "8": "b", "(": "c", "3": "e", "6": "g",
            "1": "l", "!": "i", "0": "o", "5": "s", "$": "s", "7": "t", "+": "t",
        ]
        return String(input.map { substitutions[$0] ?? $0 })
    }

    /// Drops leading and trailing decoration: `1password2024!` → `password`.
    private static func trimmingNonLetters(_ input: String) -> String {
        var folded = input
        while let last = folded.last, !last.isLetter {
            folded.removeLast()
        }
        while let first = folded.first, !first.isLetter {
            folded.removeFirst()
        }
        return folded
    }

    /// True when the password leans on the account's own identity.
    private static func containsIdentity(_ lowered: String, email: String) -> Bool {
        let localPart = email.lowercased()
            .split(separator: "@").first.map(String.init) ?? email.lowercased()
        // Split on separators so "ashutosh.anand" also guards "ashutosh".
        let fragments = localPart
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 4 }
        if lowered.contains(localPart) && localPart.count >= 4 { return true }
        return fragments.contains { lowered.contains($0) }
    }

    private static func distinctCharacterCount(_ input: String) -> Int {
        Set(input).count
    }

    /// Ascending or descending runs of code points: `123456`, `abcdef`, `fedcba`.
    private static func isRun(_ input: String) -> Bool {
        let scalars = input.unicodeScalars.map { Int($0.value) }
        guard scalars.count >= minimumLength else { return false }
        let deltas = zip(scalars, scalars.dropFirst()).map { $1 - $0 }
        return deltas.allSatisfy { $0 == 1 } || deltas.allSatisfy { $0 == -1 }
    }

    /// Contiguous slices of a keyboard row — `qwerty`, `asdfgh`, `zxcvbn`.
    private static func isKeyboardWalk(_ input: String) -> Bool {
        guard input.count >= 4 else { return false }
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm", "1234567890"]
        return rows.contains { row in
            row.contains(input) || String(row.reversed()).contains(input)
        }
    }

    // MARK: Scoring

    /// Rough guessability signal for the meter, once the hard rules pass.
    /// Deliberately simple — the blocklist above does the real work.
    private static func score(_ password: String) -> Strength {
        var points = 0

        switch password.count {
        case 16...: points += 3
        case 12..<16: points += 2
        default: points += 1
        }

        if password.contains(where: \.isLowercase) { points += 1 }
        if password.contains(where: \.isUppercase) { points += 1 }
        if password.contains(where: \.isNumber) { points += 1 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber }) { points += 1 }
        // Variety matters more than any single class.
        if distinctCharacterCount(password) >= 10 { points += 1 }

        switch points {
        case 6...: return .strong
        case 4...5: return .fair
        default: return .weak
        }
    }

    // MARK: Data

    private static let brandTerms = ["peptide", "riva", "thepeptidecompany", "tpc", "glp"]

    /// The head of the real-world leaked-password distribution. A list this
    /// size covers the passwords that actually show up in credential-stuffing
    /// lists; the pattern rules above generalise past it.
    private static let commonPasswords: Set<String> = [
        "password", "passwords", "password1", "passw0rd", "pass", "passcode",
        "123456", "1234567", "12345678", "123456789", "1234567890", "12345",
        "qwerty", "qwertyui", "qwerty123", "qwertyuiop", "asdfgh", "asdfghjk",
        "zxcvbnm", "qazwsx", "qwe123", "1q2w3e4r", "1qaz2wsx", "zaq12wsx",
        "letmein", "welcome", "welcome1", "admin", "administrator", "root",
        "login", "guest", "user", "test", "testing", "temp", "changeme",
        "abc123", "abcd1234", "a1b2c3d4", "iloveyou", "princess", "sunshine",
        "monkey", "dragon", "master", "shadow", "football", "baseball",
        "basketball", "soccer", "hockey", "jordan", "michael", "jennifer",
        "michelle", "daniel", "jessica", "charlie", "thomas", "george",
        "hunter", "harley", "ranger", "buster", "batman", "superman",
        "trustno1", "starwars", "pokemon", "computer", "internet", "samsung",
        "google", "facebook", "instagram", "whatsapp", "snapchat", "twitter",
        "apple", "iphone", "android", "windows", "microsoft", "linkedin",
        "freedom", "whatever", "qwaszx", "asdf", "asdfasdf", "aaaaaa",
        "aaaaaaaa", "111111", "1111111", "11111111", "000000", "0000",
        "121212", "123123", "112233", "654321", "666666", "696969",
        "777777", "888888", "999999", "555555", "222222", "333333",
        "444444", "101010", "123321", "789456", "159753", "147258",
        "secret", "summer", "winter", "spring", "autumn", "january",
        "february", "december", "november", "october", "september",
        "chocolate", "cookie", "flower", "banana", "orange", "purple",
        "yellow", "silver", "golden", "diamond", "phoenix", "cheese",
        "pepper", "ginger", "cowboy", "eagle", "tiger", "lion",
        "matrix", "ninja", "hello", "helloworld", "goodbye", "please",
        "money", "loveme", "lovely", "forever", "family", "friend",
        "angel", "heaven", "jesus", "church", "india", "mumbai",
        "delhi", "bangalore", "chennai", "kolkata", "america", "canada",
        "london", "paris", "berlin", "tokyo", "sydney", "moscow",
        "liverpool", "arsenal", "chelsea", "barcelona", "realmadrid",
        "manchester", "cricket", "tennis", "fitness", "workout",
        "healthy", "health", "weightloss", "ozempic", "wegovy",
        "mounjaro", "zepbound", "semaglutide", "tirzepatide", "insulin",
        "doctor", "nurse", "medicine", "hospital", "patient",
    ]
}
