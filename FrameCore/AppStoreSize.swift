import Foundation

/// App Store Connect のスクリーンショット提出サイズ。
/// 出典: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
/// （Apple のページに無い値は載せない。Apple 側の更新で変わるので、提出前に最新の仕様を確認すること）
nonisolated public struct AppStoreSize: Identifiable, Hashable, Sendable {
    public enum Family: String, CaseIterable, Sendable {
        case iPhone = "iPhone", iPad = "iPad", mac = "Mac", watch = "Apple Watch"
    }

    public var family: Family
    /// 例: "Dynamic Island（大）"
    public var label: String
    /// 縦向きの寸法。Mac / Apple Watch は仕様上この向きのみ。
    public var width: Int
    public var height: Int
    public var isRequired = false

    public var id: String { "\(family.rawValue)-\(width)x\(height)" }
    public var title: String { "\(label) \(width)×\(height)" }

    /// iPhone / iPad はベゼルの向きに合わせて縦長・横長にする（仕様の寸法は縦向き表記）。
    /// Swift の `case a, b where cond` は where が最後のパターンにしか掛からないので、family と向きを分けて判定する。
    public func canvas(for orientation: BezelOrientation) -> (width: Int, height: Int) {
        guard family == .iPhone || family == .iPad else { return (width, height) }
        let short = min(width, height), long = max(width, height)
        return orientation == .landscape ? (long, short) : (short, long)
    }

    private static func make(_ family: Family, _ label: String, _ sizes: [(Int, Int)], required: Set<Int> = []) -> [AppStoreSize] {
        sizes.map { AppStoreSize(family: family, label: label, width: $0.0, height: $0.1, isRequired: required.contains($0.0)) }
    }

    public static let all: [AppStoreSize] =
        make(.iPhone, "Dynamic Island（大）", [(1320, 2868), (1290, 2796), (1260, 2736)])
        + make(.iPhone, "Dynamic Island（中）", [(1179, 2556), (1206, 2622)], required: [1179]) // 1179×2556 は iPhone の必須サイズ
        + make(.iPhone, "Face ID（大）", [(1284, 2778), (1242, 2688)])
        + make(.iPhone, "Face ID（中）", [(1170, 2532), (1125, 2436), (1080, 2340)])
        + make(.iPhone, "ホームボタン（大）", [(1242, 2208)])
        + make(.iPhone, "ホームボタン（中）", [(750, 1334)])
        + make(.iPad, "13インチ", [(2064, 2752), (2048, 2732)], required: [2064]) // iPad アプリでは 13 インチが必須
        + make(.iPad, "11インチ", [(1488, 2266), (1512, 2316), (1668, 2420), (1668, 2388), (1640, 2360)])
        + make(.iPad, "10.5インチ", [(1668, 2224)])
        + make(.iPad, "9.7インチ", [(1536, 2048)])
        + make(.mac, "16:10", [(1280, 800), (1440, 900), (2560, 1600), (2880, 1800)])
        + [
            AppStoreSize(family: .watch, label: "Ultra 4 / 3", width: 422, height: 514),
            AppStoreSize(family: .watch, label: "Ultra 2 / Ultra", width: 410, height: 502),
            AppStoreSize(family: .watch, label: "Series 12 / 11 / 10", width: 416, height: 496),
            AppStoreSize(family: .watch, label: "Series 9 / 8 / 7", width: 396, height: 484),
            AppStoreSize(family: .watch, label: "Series 6 / 5 / 4 / SE", width: 368, height: 448),
            AppStoreSize(family: .watch, label: "Series 3 / 2 / 1", width: 312, height: 390),
        ]

    public static func find(id: String?) -> AppStoreSize? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}
