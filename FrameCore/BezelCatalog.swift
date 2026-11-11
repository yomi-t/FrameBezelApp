import Foundation

/// Apple 配布のフォルダ構成（`機種名/機種名 - 色 - Portrait.png`）の名前解析。
nonisolated public struct BezelMeta: Equatable, Sendable {
    public var model: String?
    public var color: String?
    public var orientation: BezelOrientation?
}

nonisolated public enum BezelNaming {
    private static let separator = " - "

    /// `folderName` は PNG を直接含むフォルダ名（機種名）。Portrait/Landscape という名前のフォルダは
    /// 呼び出し側で飛ばしてから渡す。フォルダが無い単体追加では nil を渡す。
    public static func parse(fileName: String, folderName: String?) -> BezelMeta {
        let base = (fileName as NSString).deletingPathExtension
        var parts = base.components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var orientation: BezelOrientation?
        parts.removeAll { part in
            switch part.lowercased() {
            case "portrait": orientation = .portrait; return true
            case "landscape": orientation = .landscape; return true
            default: return false
            }
        }

        let model: String?
        if let folderName, !folderName.isEmpty {
            model = folderName
        } else if parts.count >= 2 {
            model = parts.removeFirst()
        } else {
            // "Bezel-iPhone-17.png" のような旧来の名前は機種として解釈しない
            return BezelMeta(model: nil, color: nil, orientation: orientation)
        }
        if let model { parts.removeAll { $0.caseInsensitiveCompare(model) == .orderedSame } }

        let color = parts.isEmpty ? nil : parts.joined(separator: " ")
        return BezelMeta(model: model, color: color, orientation: orientation)
    }
}

/// 機種ごとにまとめた一覧と、向き・色の選択ロジック。UI 非依存。
nonisolated public struct BezelModelGroup: Identifiable, Equatable, Sendable {
    public var model: String
    public var bezels: [Bezel]
    public var id: String { model }

    /// サムネイル用。縦向きを優先し、その中で先頭。
    public var representative: Bezel {
        bezels.first { $0.effectiveOrientation == .portrait } ?? bezels[0]
    }

    public var orientations: [BezelOrientation] {
        BezelOrientation.allCases.filter { o in bezels.contains { $0.effectiveOrientation == o } }
    }

    /// 指定の向きで選べる色。色違いが無ければ空。
    public func colors(for orientation: BezelOrientation) -> [String] {
        var seen: [String] = []
        for b in bezels where b.effectiveOrientation == orientation {
            if let c = b.color, !seen.contains(c) { seen.append(c) }
        }
        return seen
    }

    /// 向き・色の希望に最も近いベゼル。希望が無ければ（無い組み合わせなら）近いものにフォールバック。
    public func pick(orientation: BezelOrientation?, color: String?) -> Bezel {
        let sameOrientation = orientation.map { o in bezels.filter { $0.effectiveOrientation == o } } ?? []
        let pool = sameOrientation.isEmpty ? bezels : sameOrientation
        if let color, let hit = pool.first(where: { $0.color == color }) { return hit }
        return pool.first { $0.effectiveOrientation == .portrait } ?? pool[0]
    }

    /// スクショの縦横比に最も近い画面領域を持つ向きのベゼル（色は希望を優先）。
    /// どの向きも許容差に入らないときも、最も近いものを返す。
    public func bestMatch(screenshotWidth: Int, screenshotHeight: Int, color: String?) -> Bezel {
        let candidates = orientations.map { pick(orientation: $0, color: color) }
        let scored = candidates.compactMap { b -> (Bezel, Double)? in
            AspectMatcher.relativeDifference(screenshotWidth: screenshotWidth, screenshotHeight: screenshotHeight,
                                             aperture: b.aperture).map { (b, $0) }
        }
        return scored.min { $0.1 < $1.1 }?.0 ?? pick(orientation: nil, color: color)
    }
}

nonisolated public enum BezelCatalog {
    /// 既に整列済みの一覧から、出現順を保って機種ごとにまとめる。
    public static func groups(_ bezels: [Bezel]) -> [BezelModelGroup] {
        var order: [String] = []
        var map: [String: [Bezel]] = [:]
        for b in bezels {
            let key = b.modelName
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(b)
        }
        return order.map { BezelModelGroup(model: $0, bezels: map[$0] ?? []) }
    }
}
