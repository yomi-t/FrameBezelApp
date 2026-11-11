import Foundation

/// Apple 配布のフォルダ構成（`機種名/機種名 - 色 - Portrait.png`）の名前解析。
nonisolated public struct BezelMeta: Equatable, Sendable {
    public var model: String?
    public var color: String?
    public var orientation: BezelOrientation?
    /// 画面の形態（Duo の `Inner Open` など）。無ければ nil
    public var variant: String?
}

nonisolated public enum BezelNaming {
    private static let separator = " - "
    /// 色の後ろに付く画面の形態（Duo）。この並びが選択肢の表示順になる。
    public static let knownVariants = ["Inner Open", "Outer Closed", "Outer Open"]

    /// 形態の表示名。未知の形態はそのまま出す。
    public static func variantLabel(_ variant: String) -> String {
        switch variant {
        case "Inner Open": "内側の画面・開く"
        case "Outer Closed": "外側の画面・閉じる"
        case "Outer Open": "外側の画面・開く"
        default: variant
        }
    }
    /// 機種名として使わないフォルダ名（Apple の dmg の構成上のフォルダ）
    static let genericFolderNames: Set<String> = ["png", "photoshop", "portrait", "landscape"]

    /// 機種の名前から、配布物由来の `Bezel` の接頭辞（`Bezel-` / `Bezel ` / `Bezel_`）を除く。機種の正式名称だけにする。
    public static func officialName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespaces)
        while let r = name.range(of: #"^bezel[-_ ]+"#, options: [.regularExpression, .caseInsensitive]) {
            name.removeSubrange(r)
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// 機種名ではないフォルダか。上のフォルダ名に加え、dmg 名由来の `Bezel-iPhone-11` のような名前も機種名にしない。
    static func isGenericFolder(_ name: String) -> Bool {
        let lower = name.lowercased()
        return name.isEmpty || genericFolderNames.contains(lower) || lower.hasPrefix("bezel")
    }

    /// 機種・色・向きをファイル名とフォルダ名から決める。
    /// - ファイル名が `機種 - 色 - 向き` のように 2 つ以上に区切れるときは、先頭を機種名とする（フォルダ名より優先）。
    ///   Apple の配布はフォルダが機種名でないこと（`PNG` 直下に並ぶ、バンド名のサブフォルダなど）があるため。
    /// - 区切れないとき: `MacBook Air M5 13-inch Midnight` や `Studio Display 2026 On Dark Background` の書式を解釈し、
    ///   それも当てはまらなければ、機種名らしいフォルダ名（`folderName`）を機種とし、ファイル名の残りは色とする。
    /// - 向きは `Portrait` / `Landscape`、または `Inner Open Landscape` のような末尾。後者の `Inner Open` は色の一部になる。
    /// - 機種を決められない旧来の名前（`Bezel-iPhone-17.png`）は機種なしで返す。
    public static func parse(fileName: String, folderName: String?) -> BezelMeta {
        let base = (fileName as NSString).deletingPathExtension
        var parts = base.components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var orientation: BezelOrientation?
        parts = parts.compactMap { part in
            let lower = part.lowercased()
            if lower == "portrait" { orientation = .portrait; return nil }
            if lower == "landscape" { orientation = .landscape; return nil }
            for (suffix, value) in [(" portrait", BezelOrientation.portrait), (" landscape", .landscape)] where lower.hasSuffix(suffix) {
                orientation = value
                return String(part.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            }
            return part
        }

        let folder = folderName.flatMap { isGenericFolder($0) ? nil : $0 }
        var model: String?
        var rest: [String] = []

        if parts.count >= 2 {
            model = parts[0]
            rest = Array(parts.dropFirst())
        } else if parts.count == 1 {
            let part = parts[0]
            if let inline = splitInline(part) {
                model = inline.model
                rest = inline.color.map { [$0] } ?? []
            } else if let folder {
                if related(folder, part) {
                    model = part
                } else {
                    model = folder
                    rest = [part]
                }
            } else if orientation != nil {
                model = part // `iPhone 11 - Portrait.png` のように機種名と向きだけ
            }
        } else {
            model = folder
        }

        guard var model = model.map(officialName), !model.isEmpty else { return BezelMeta(model: nil, color: nil, orientation: orientation) }
        // Apple Watch: `42mm` などのサイズは画面が違うので機種の一部にする
        if let first = rest.first, first.range(of: #"^\d+mm$"#, options: .regularExpression) != nil {
            model += " " + first
            rest.removeFirst()
        }
        // MacBook の世代（`4th Gen` / `4th Gen (2019)`）も機種の一部。色と混ざらないようにする
        if let first = rest.first, first.range(of: #"^\d+(st|nd|rd|th) Gen( \(\d{4}\))?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            model += " " + first
            rest.removeFirst()
        }
        if model.hasPrefix("AW ") { model = "Apple Watch " + model.dropFirst(3) }
        rest.removeAll { $0.caseInsensitiveCompare(model) == .orderedSame }
        var color = rest.isEmpty ? nil : rest.joined(separator: " ")
        // `Night Sky Inner Open` → 色 `Night Sky` + 形態 `Inner Open`
        var variant: String?
        if let text = color {
            for v in knownVariants {
                if text.caseInsensitiveCompare(v) == .orderedSame {
                    variant = v; color = nil; break
                }
                if text.lowercased().hasSuffix(" " + v.lowercased()) {
                    variant = v
                    color = String(text.dropLast(v.count + 1)).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }
        return BezelMeta(model: model, color: color, orientation: orientation, variant: variant)
    }

    /// 区切りの無い名前を機種と色に分ける。色が無い名前（`MacBook Pro Intel 15-inch`）は、全体を機種名にする。
    private static func splitInline(_ name: String) -> (model: String, color: String?)? {
        // `MacBook Air M2 13-inch Midnight` → 「…-inch」までが機種
        if let r = name.range(of: #"^.+?-inch(?= )"#, options: .regularExpression) {
            let color = name[r.upperBound...].trimmingCharacters(in: .whitespaces)
            if !color.isEmpty { return (String(name[r]), color) }
        }
        if name.range(of: #"^.+-inch$"#, options: .regularExpression) != nil { return (name, nil) }
        // `Studio Display 2026 On Dark Background` → 背景の明暗が色の違い
        if let r = name.range(of: #" On (Dark|Light) Background$"#, options: .regularExpression) {
            let color = name[r].replacingOccurrences(of: " On ", with: "")
            return (String(name[..<r.lowerBound]), color)
        }
        return nil
    }

    /// 英数字だけにして比べ、片方がもう片方を含むか（`Bezel-iPhone-11` と `iPhone 11` など）。
    private static func related(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let (x, y) = (norm(a), norm(b))
        return !x.isEmpty && !y.isEmpty && (x.contains(y) || y.contains(x))
    }
}

/// 向きを指定してベゼルを選んだ結果。その向きが登録されていなければ、逆向きの登録ベゼルを回して使う。
nonisolated public struct BezelSelection: Equatable, Sendable {
    /// 登録されているベゼル（保存データそのもの）
    public var registered: Bezel
    /// 使う向き。`registered` と違えば回転して使う
    public var orientation: BezelOrientation

    public var isRotated: Bool { registered.effectiveOrientation != orientation }
    /// 実際に使うベゼル定義（回転が要るなら回した定義）
    public var resolved: Bezel { registered.turned(to: orientation) }
    /// 登録画像を `resolved` に合わせるための、時計回りの 90° 単位の回転
    public var rotation: Rotation { Rotation(quarterTurns: registered.quarterTurns(to: orientation)) }
}

/// 機種ごとにまとめた一覧と、向き・色の選択ロジック。UI 非依存。
nonisolated public struct BezelModelGroup: Identifiable, Equatable, Sendable {
    public var model: String
    public var bezels: [Bezel]
    public var id: String { model }
    public var category: DeviceCategory { DeviceCategory.of(modelName: model) }

    /// 画面の形態（Duo の内側・外側など）。無ければ空。表示順は `BezelNaming.knownVariants` の並び、未知のものは後ろに名前順。
    public var variants: [String] {
        let all = Set(bezels.compactMap(\.variant))
        let known = BezelNaming.knownVariants.filter(all.contains)
        return known + all.subtracting(known).sorted()
    }

    /// 指定の形態のベゼル。形態を指定しない（または無い形態の）ときは、先頭の形態。形態が無い機種は全部。
    private func pool(variant: String?) -> [Bezel] {
        guard let first = variants.first else { return bezels }
        let wanted = variant.flatMap { v in variants.contains(v) ? v : nil } ?? first
        return bezels.filter { $0.variant == wanted }
    }

    /// サムネイル用。先頭の形態の縦向きを優先し、その中で先頭。
    public var representative: Bezel {
        let p = pool(variant: nil)
        return p.first { $0.effectiveOrientation == .portrait } ?? p.first ?? bezels[0]
    }

    /// 全形態を通して選べる向き。
    public var orientations: [BezelOrientation] {
        BezelOrientation.allCases.filter { o in bezels.contains { $0.effectiveOrientation == o } }
    }

    /// 指定の形態で選べる向き（形態によっては縦だけ、など）。
    public func orientations(variant: String?) -> [BezelOrientation] {
        let p = pool(variant: variant)
        return BezelOrientation.allCases.filter { o in p.contains { $0.effectiveOrientation == o } }
    }

    /// 指定の向き（と形態）で選べる色。色違いが無ければ空。
    public func colors(for orientation: BezelOrientation, variant: String? = nil) -> [String] {
        var seen: [String] = []
        for b in pool(variant: variant) where b.effectiveOrientation == orientation {
            if let c = b.color, !seen.contains(c) { seen.append(c) }
        }
        return seen
    }

    /// 向き・色・形態の希望に最も近いベゼル。希望が無ければ（無い組み合わせなら）近いものにフォールバック。
    public func pick(orientation: BezelOrientation?, color: String?, variant: String? = nil) -> Bezel {
        let base = pool(variant: variant)
        let sameOrientation = orientation.map { o in base.filter { $0.effectiveOrientation == o } } ?? []
        let candidates = sameOrientation.isEmpty ? base : sameOrientation
        if let color, let hit = candidates.first(where: { $0.color == color }) { return hit }
        return candidates.first { $0.effectiveOrientation == .portrait } ?? candidates[0]
    }

    /// 向きが未登録のとき、逆向きを回して使えるか。向きが固定のデバイス（Mac・Watch など）は回さない。
    public var allowsRotation: Bool { category.rotates }

    /// 指定の向きで選ぶ。向きが登録されていなければ、逆向きのベゼルを回して対応する（色・形態は `pick` と同じ）。
    /// 向きが固定のデバイスは回さず、登録されているベゼルをそのまま使う。
    public func selection(orientation: BezelOrientation, color: String?, variant: String? = nil) -> BezelSelection {
        let bezel = pick(orientation: orientation, color: color, variant: variant)
        return BezelSelection(registered: bezel, orientation: allowsRotation ? orientation : bezel.effectiveOrientation)
    }

    /// 向きの選択肢。回せるデバイス（iPhone・iPad）は、登録が片方だけでも回転すれば両方になるので縦・横の両方。
    /// 固定のデバイスは、登録されている向きだけ（1 つなら選択肢を出さない）。
    public func selectableOrientations(variant: String? = nil) -> [BezelOrientation] {
        allowsRotation ? BezelOrientation.allCases : orientations(variant: variant)
    }

    /// 選べる色。その向きが登録されていないときは、回転元になる向きの色を出す。
    public func selectableColors(for orientation: BezelOrientation, variant: String? = nil) -> [String] {
        let own = colors(for: orientation, variant: variant)
        if !own.isEmpty { return own }
        guard allowsRotation else { return [] }
        let p = pool(variant: variant)
        if p.contains(where: { $0.effectiveOrientation == orientation }) { return [] }
        let other: BezelOrientation = orientation == .portrait ? .landscape : .portrait
        return colors(for: other, variant: variant)
    }

    /// スクショの縦横比に最も近い画面領域になる向きを選ぶ。登録されていない向きは回転して比べる。
    /// 回転が要らない候補が、回転する候補とほぼ同じ（差 0.5% 以内）なら、登録どおりのものを優先する。
    public func bestSelection(screenshotWidth: Int, screenshotHeight: Int, color: String?, variant: String? = nil) -> BezelSelection {
        let candidates = BezelOrientation.allCases.map { selection(orientation: $0, color: color, variant: variant) }
        let scored = candidates.compactMap { sel -> (BezelSelection, Double)? in
            AspectMatcher.relativeDifference(screenshotWidth: screenshotWidth, screenshotHeight: screenshotHeight,
                                             aperture: sel.resolved.aperture).map { (sel, $0) }
        }
        guard let best = scored.min(by: { $0.1 < $1.1 }) else {
            return selection(orientation: pick(orientation: nil, color: color, variant: variant).effectiveOrientation, color: color, variant: variant)
        }
        if best.0.isRotated, let plain = scored.filter({ !$0.0.isRotated }).min(by: { $0.1 < $1.1 }), plain.1 <= best.1 + 0.005 {
            return plain.0
        }
        return best.0
    }

    /// スクショの縦横比に最も近い画面領域を持つ向きのベゼル（色・形態は希望を優先）。
    /// どの向きも許容差に入らないときも、最も近いものを返す。
    public func bestMatch(screenshotWidth: Int, screenshotHeight: Int, color: String?, variant: String? = nil) -> Bezel {
        let candidates = orientations(variant: variant).map { pick(orientation: $0, color: color, variant: variant) }
        let scored = candidates.compactMap { b -> (Bezel, Double)? in
            AspectMatcher.relativeDifference(screenshotWidth: screenshotWidth, screenshotHeight: screenshotHeight,
                                             aperture: b.aperture).map { (b, $0) }
        }
        return scored.min { $0.1 < $1.1 }?.0 ?? pick(orientation: nil, color: color, variant: variant)
    }
}

nonisolated public enum BezelCatalog {
    /// 一覧にある種類（`DeviceCategory` の定義順）。
    public static func categories(_ groups: [BezelModelGroup]) -> [DeviceCategory] {
        DeviceCategory.allCases.filter { c in groups.contains { $0.category == c } }
    }

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
