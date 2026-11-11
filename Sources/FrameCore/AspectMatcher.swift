import Foundation

/// スクショと画面領域の縦横比の比較、および合うベゼルの探索。UI に依存しない純粋なロジック。
public enum AspectMatcher {
    /// 相対差がこの値以下なら「一致」とみなす（1%）。
    /// 現行 iPhone の画面比は 0.460〜0.462 に収まり（同世代内の差は 0.5% 未満）、
    /// 自動検出の数px誤差（約0.2%）も吸収できる。一方 1% を超えると fit 時の黒帯が
    /// 長辺で数十px になり目立ち始めるため、それ以上は「不一致」として提案・切り抜きに回す。
    public static let defaultTolerance = 0.01

    /// |screenshot / aperture − 1|。幅・高さが 0 以下なら nil。
    public static func relativeDifference(
        screenshotWidth: Int, screenshotHeight: Int, aperture: Aperture
    ) -> Double? {
        guard screenshotWidth > 0, screenshotHeight > 0, aperture.width > 0, aperture.height > 0 else { return nil }
        let s = Double(screenshotWidth) / Double(screenshotHeight)
        let a = aperture.width / aperture.height
        return abs(s / a - 1)
    }

    public static func matches(
        screenshotWidth: Int, screenshotHeight: Int, aperture: Aperture, tolerance: Double = defaultTolerance
    ) -> Bool {
        guard let d = relativeDifference(screenshotWidth: screenshotWidth, screenshotHeight: screenshotHeight, aperture: aperture)
        else { return false }
        return d <= tolerance
    }

    /// 許容差内のベゼルを、差の小さい順に返す。`excluding` は現在選択中のベゼルなどを除くための bezelFile。
    public static func suggestions(
        screenshotWidth: Int, screenshotHeight: Int, from bezels: [Bezel],
        excluding excluded: String? = nil, tolerance: Double = defaultTolerance
    ) -> [Bezel] {
        bezels
            .filter { $0.bezelFile != excluded }
            .compactMap { b -> (Bezel, Double)? in
                guard let d = relativeDifference(screenshotWidth: screenshotWidth, screenshotHeight: screenshotHeight, aperture: b.aperture),
                      d <= tolerance else { return nil }
                return (b, d)
            }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }

    /// 提案 1 件。`needsRotation` が true なら、現在の向きから 90° 回すと合う（縦横を入れ替えた比で一致）。
    public struct Suggestion: Equatable, Sendable {
        public var bezel: Bezel
        public var needsRotation: Bool
    }

    /// 現在の向きで合うベゼルに加え、90° 回転すれば合うベゼルも返す（差の小さい順、同差なら回転不要を先に）。
    /// 回転不要の候補は `excluding`（選択中ベゼル）を除く。回転が要る候補は選択中ベゼル自身も含める
    /// （横向きスクショ + 縦向きベゼル選択中、のとき「回転すれば合う」を出すため）。
    public static func suggestionsAllowingRotation(
        screenshotWidth: Int, screenshotHeight: Int, from bezels: [Bezel],
        excluding excluded: String? = nil, tolerance: Double = defaultTolerance
    ) -> [Suggestion] {
        var result: [(Suggestion, Double)] = []
        for b in bezels {
            if b.bezelFile != excluded,
               let d = relativeDifference(screenshotWidth: screenshotWidth, screenshotHeight: screenshotHeight, aperture: b.aperture),
               d <= tolerance {
                result.append((Suggestion(bezel: b, needsRotation: false), d))
            }
            if let d = relativeDifference(screenshotWidth: screenshotHeight, screenshotHeight: screenshotWidth, aperture: b.aperture),
               d <= tolerance {
                result.append((Suggestion(bezel: b, needsRotation: true), d))
            }
        }
        return result
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : (!$0.0.needsRotation && $1.0.needsRotation) }
            .map { $0.0 }
    }
}
