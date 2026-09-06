import Foundation

/// Spoken money becomes a symbol and digits before the transcript reaches the
/// model: "fifteen quid a month" → "£15 a month", "four pounds fifty" → "£4.50",
/// "20 bucks" → "$20". The on-device model converts "twenty dollars" but not
/// "fifteen pounds", and no prompt wording fixed that without breaking another
/// case, so this is done here where it is deterministic.
extension TextCleanup {
    private static let currencies: [String: String] = [
        "dollar": "$", "dollars": "$", "buck": "$", "bucks": "$",
        "pound": "£", "pounds": "£", "quid": "£",
        "euro": "€", "euros": "€",
    ]

    private static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    /// Reads a number from `words[from...]`: digits, or number words up to the
    /// thousands ("two hundred and fifty", "twenty-five"). Returns the value and
    /// how many words it used, or nil when the words are not a number.
    static func spokenNumber(in words: [String], from start: Int) -> (value: Int, count: Int)? {
        guard start < words.count else { return nil }
        if let n = Int(words[start].replacingOccurrences(of: ",", with: "")) { return (n, 1) }
        var total = 0, current = 0, i = start, used = 0
        while i < words.count {
            let w = words[i].lowercased()
            let parts = w.split(separator: "-").map(String.init)
            if parts.count == 2, let t = tens[parts[0]], let u = units[parts[1]], u < 10 {
                current += t + u; i += 1; used += 1; continue
            }
            if let u = units[w] { current += u }
            else if let t = tens[w] { current += t }
            else if w == "hundred", current > 0 { current *= 100 }
            else if w == "thousand", current > 0 { total += current * 1000; current = 0 }
            else if w == "and", used > 0, i + 1 < words.count, units[words[i + 1].lowercased()] != nil || tens[words[i + 1].lowercased()] != nil { }
            else { break }
            i += 1; used += 1
        }
        guard used > 0 else { return nil }
        return (total + current, used)
    }

    /// "fifteen quid" → "£15"; "four pounds fifty" → "£4.50"; "2 dollars" → "$2".
    static func normalizeCurrency(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var i = 0
        while i < words.count {
            if let (amount, count) = spokenNumber(in: words, from: i), i + count < words.count {
                let (unitWord, suffix) = splitTrailingPunctuation(words[i + count])
                if let symbol = currencies[unitWord.lowercased()] {
                    var consumed = count + 1
                    var money = "\(symbol)\(amount)"
                    // "four pounds fifty": a number under 100 right after the unit is the minor amount.
                    if suffix.isEmpty, let (minor, minorCount) = spokenNumber(in: words, from: i + consumed), minor < 100, minorCount == 1,
                       i + consumed + 1 >= words.count || currencies[words[i + consumed + 1].lowercased()] == nil {
                        money += String(format: ".%02d", minor)
                        consumed += minorCount
                    }
                    out.append(money + suffix)
                    i += consumed
                    continue
                }
            }
            out.append(words[i])
            i += 1
        }
        return out.joined(separator: " ")
    }

    private static func splitTrailingPunctuation(_ word: String) -> (String, String) {
        var w = Substring(word), suffix = ""
        while let last = w.last, !last.isLetter, !last.isNumber { suffix = String(last) + suffix; w = w.dropLast() }
        return (String(w), suffix)
    }
}
