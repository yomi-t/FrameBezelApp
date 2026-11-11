import Foundation

/// 機種を新しい順に並べるための目安。機種名には発売日が入っていないので、名前から読める世代（iPhone の数字、チップ、
/// Series や Ultra の番号、年）を発売年に置き換えて比べる。製品系列をまたぐと世代の数字だけではずれるものは、
/// `yearOverrides` で発売年を決めている（推定を含む。ずれていたらここを直す）。
nonisolated public enum ModelOrder {
    /// 大きいほど新しい。`年 × 100 + 同じ年の中での格`。読み取れない機種は 0（一番下）。
    public static func score(of modelName: String) -> Double {
        let name = modelName.lowercased()
        let year = releaseYear(of: name)
        guard year > 0 else { return 0 }
        return year * 100 + tier(of: name)
    }

    /// 新しい順。同じ得点なら、名前の自然順の逆（`46mm` が `42mm` より上、`13"` が `11"` より上）。
    public static func sortedNewestFirst(_ groups: [BezelModelGroup]) -> [BezelModelGroup] {
        groups.sorted { a, b in
            let (x, y) = (score(of: a.model), score(of: b.model))
            if x != y { return x > y }
            return a.model.localizedStandardCompare(b.model) == .orderedDescending
        }
    }

    // MARK: 発売年

    /// 製品系列をまたぐと、世代の数字から求めた年がずれるもの（機種名の部分一致、すべて小文字）。
    /// 上から順に最初に当てはまったものを使う。
    static let yearOverrides: [(keywords: [String], year: Double)] = [
        (["ipad (a16)"], 2025),
        (["ipad mini", "(a17"], 2024),
        (["ipad mini", "(a20"], 2026),
        (["ipad air", "(m2)"], 2024),
        (["ipad air", "(m3)"], 2025),
        (["ipad air", "(m4)"], 2026),
        (["macbook air", " m3"], 2024),
        (["macbook air", " m4"], 2025),
        (["macbook air", " m5"], 2026),
        (["macbook pro", " m1"], 2021), // 14・16 インチの M1 Pro / Max（2021）
        (["intel"], 2018),              // Intel 搭載の MacBook（Touch Bar 世代）
        (["macbook neo"], 2026),
        (["proled"], 2026),
        (["ultra 4"], 2026),
        (["ultra 3"], 2025),
        (["ultra 2"], 2023),
    ]

    static func releaseYear(of name: String) -> Double {
        // 年が名前に入っているもの（`Studio Display 2026`、`4th Gen (2019)`）
        if let y = firstMatch(#"\b(20\d\d)\b"#, in: name).flatMap(Double.init) { return y }
        for o in yearOverrides where o.keywords.allSatisfy({ name.contains($0) }) { return o.year }

        if name.hasPrefix("iphone") {
            if name.contains("duo") { return 2026 }
            if name.contains("air") { return 2025 }
            if let n = firstMatch(#"iphone (\d+)"#, in: name).flatMap(Double.init) { return 2008 + n } // 11 → 2019 … 18 → 2026
            return 0
        }
        if name.hasPrefix("ipad") {
            if let n = firstMatch(#"\(m(\d+)\)"#, in: name).flatMap(Double.init) { return 2020 + n }  // M1 → 2021 … M5 → 2025
            if let n = firstMatch(#"\(a(\d+)"#, in: name).flatMap(Double.init) { return 2006 + n }    // A15 → 2021 … A20 → 2026
            return 2020 // 世代の分からない旧機種
        }
        if name.hasPrefix("apple watch") || name.hasPrefix("aw ") {
            if name.contains("ultra") {
                return 2022 // Ultra（初代）。Ultra 2 以降は上の置き換えで決まる
            }
            if let n = firstMatch(#"(?:series |\bs)(\d+)"#, in: name).flatMap(Double.init) { return 2014 + n } // Series 8 → 2022 … 11 → 2025
            return 0
        }
        if ["macbook", "imac", "mac ", "studio display", "pro display"].contains(where: { name.hasPrefix($0) }) {
            if let n = firstMatch(#"\bm(\d)\b"#, in: name).flatMap(Int.init) {
                return [1: 2020, 2: 2022, 3: 2023, 4: 2024, 5: 2025][n] ?? Double(2020 + n)
            }
            if name.contains("5th gen") { return 2021 }
            if name.contains("4th gen") { return 2018 }
            return 0
        }
        return 0
    }

    /// 同じ年の中での並び（大きいほど上）。上位機種ほど上。
    static func tier(of name: String) -> Double {
        if name.hasPrefix("iphone") {
            if name.contains("duo") { return 7 }
            if name.contains("pro max") { return 6 }
            if name.contains("pro") { return 5 }
            if name.contains("air") { return 4 }
            if name.contains("plus") { return 3 }
            if name.contains("mini") || name.range(of: #"\d+e\b"#, options: .regularExpression) != nil { return 1 }
            return 2
        }
        if name.hasPrefix("ipad") {
            // `iPad mini (A20 Pro)` の Pro はチップ名なので、mini を先に判定する
            if name.contains("mini") { return 1 }
            if name.hasPrefix("ipad pro") { return 4 }
            if name.contains("air") { return 3 }
            return 2
        }
        if name.hasPrefix("apple watch") || name.hasPrefix("aw ") {
            return name.contains("ultra") ? 2 : 1
        }
        if name.contains("macbook pro") { return 5 }
        if name.contains("macbook air") { return 4 }
        if name.contains("macbook") { return 3 } // Neo など
        if name.contains("imac") { return 2 }
        return 1
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
