/// Generates the short key sequences shown on hints.
///
/// Port of Vimium's `hintStrings` via Vimac's `AlphabetHints.swift` (GPL-3.0):
/// labels are prefix-free (typing one never matches the start of another)
/// and differ in length by at most one character.
public nonisolated enum HintLabels {
    /// Home-row biased, easy-to-reach characters (Vimac's default).
    public static let defaultCharacters = "sadfjklewcmpgh"

    /// Returns `count` uppercase labels, shortest first.
    public static func make(count: Int, characters: String) -> [String] {
        guard count > 0, !characters.isEmpty else { return [] }

        // Breadth-first expansion: each consumed label is replaced by itself
        // prefixed with every character, until enough unconsumed labels remain.
        var labels = [""]
        var offset = 0
        while labels.count - offset < count || labels.count == 1 {
            let label = labels[offset]
            offset += 1
            for character in characters {
                labels.append(String(character) + label)
            }
        }

        return labels[offset..<(offset + count)]
            .sorted()
            // Reversing spreads the first typed character across all labels.
            .map { String($0.reversed()).uppercased() }
            .sorted { $0.count < $1.count }
    }
}
