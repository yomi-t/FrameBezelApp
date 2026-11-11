import Foundation

/// 機種の種類。機種名から自動で決める（保存データには持たないので、取り込み済みのベゼルもそのまま分類される）。
nonisolated public enum DeviceCategory: String, CaseIterable, Identifiable, Sendable {
    case iPhone, iPad, mac, watch, other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .mac: "Mac"
        case .watch: "Watch"
        case .other: "その他"
        }
    }

    /// 持ち方で縦横が変わり、画面の表示も回るデバイスか。Mac・Apple Watch・Apple TV などは向きが固定なので、向きの選択も回転もしない。
    public var rotates: Bool { self == .iPhone || self == .iPad }

    /// 種類のタブの中で表示する短い名前。種類の名前が先頭にある機種は、その語を省く
    /// （iPhone タブなら `iPhone 17 Pro Max` → `17 Pro Max`）。省くと意味が通らない名前（`iPad (A16)` → `(A16)`）はそのまま。
    /// 保存や書き出しには使わず、一覧の見やすさのためだけの表示名。Mac は `MacBook` などが名前の一部なので省かない。
    public func shortName(of modelName: String) -> String {
        let prefix: String
        switch self {
        case .iPhone: prefix = "iPhone "
        case .iPad: prefix = "iPad "
        case .watch: prefix = "Apple Watch "
        default: return modelName
        }
        guard modelName.range(of: prefix, options: [.anchored, .caseInsensitive]) != nil else { return modelName }
        let rest = String(modelName.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty || rest.hasPrefix("(") ? modelName : rest
    }

    /// 機種名の先頭で判定する。`iMac` や `Studio Display` など、名前に Mac を含まない Mac 製品も Mac に入れる。
    public static func of(modelName: String) -> DeviceCategory {
        let name = modelName.lowercased()
        if name.hasPrefix("iphone") { return .iPhone }
        if name.hasPrefix("ipad") { return .iPad }
        if name.hasPrefix("apple watch") || name.hasPrefix("aw ") { return .watch }
        if ["macbook", "imac", "mac ", "mac studio", "mac mini", "mac pro", "studio display", "pro display"].contains(where: { name.hasPrefix($0) })
            || name == "mac" {
            return .mac
        }
        return .other
    }
}
