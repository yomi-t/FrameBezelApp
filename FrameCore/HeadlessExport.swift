import Foundation
import CoreGraphics

/// コマンドライン（画面なし）での書き出し。AI やスクリプトから使えるよう、引数の解釈と実行を UI から分けてある。
nonisolated public struct ExportRequest: Equatable, Sendable {
    public var screenshot: URL
    public var output: URL?
    /// 機種名（大文字小文字は区別しない）。登録機種が 1 つだけなら省略できる
    public var model: String?
    public var orientation: BezelOrientation?
    public var color: String?
    /// 画面の形態（Duo の `Inner Open` など）。省略時は先頭の形態
    public var variant: String?
    /// 書き出しサイズ（px）。nil はベゼル PNG の元サイズ
    public var canvas: Canvas?
    /// true なら「埋める」。既定は「収める」
    public var fill = false
    public var background: BackgroundStyle = .transparent

    nonisolated public struct Canvas: Equatable, Sendable {
        public var width: Int
        public var height: Int
    }
}

nonisolated public enum CommandLineCommand: Equatable, Sendable {
    case help
    case listModels
    case listSizes
    case export(ExportRequest)
}

nonisolated public enum CommandLineError: Error, LocalizedError, Equatable {
    case usage(String)
    case failure(String)

    public var errorDescription: String? {
        switch self {
        case .usage(let m), .failure(let m): return m
        }
    }
}

nonisolated public enum HeadlessExport {
    public static let usage = """
    使い方: FrameBezelApp --export <スクショ> [オプション]
            FrameBezelApp --list-models | --list-sizes | --help

    --export <path>        スクショ（PNG / JPEG）を指定すると、画面を開かずに書き出して終了します
    --output <path>        出力先の PNG（既に有れば上書き）。省略時はカレントフォルダに {元名}_{機種名}[_WxH].png
    --model <name>         機種名（--list-models で確認）。登録が 1 機種だけなら省略可
    --orientation <o>      portrait | landscape。省略時はスクショの縦横比に近い向き。その向きのベゼルが未登録なら、逆向きを回転して使います
    --color <name>         フレームの色。省略時は先頭の色
    --variant <name>       画面の形態（iPhone Duo の "Inner Open" | "Outer Closed" | "Outer Open"）。省略時は先頭の形態
    --size <WxH>           書き出しサイズ（例: 1320x2868）。App Store の iPhone / iPad サイズは、ベゼルの向きに合わせて縦横が決まります。
                           省略時はベゼル PNG の元サイズ。指定すると不透明（アルファ無し）の PNG になります
    --fill                 スクショを画面領域いっぱいに埋める（省略時は全体が収まる大きさ）
    --background <spec>    transparent（既定）| #RRGGBB | gradient:#RRGGBB,#RRGGBB[,角度]
                           --size 指定時、transparent の余白は白で埋まります

    終了コード: 0 = 成功、1 = 失敗、2 = 引数の誤り。成功時は出力パスを標準出力に 1 行で表示します。
    """

    /// コマンドラインで動かすべき起動か（UI を出さない）。Xcode が付ける `-NS…` などの引数では動かさない。
    public static func isCommandLineInvocation(_ arguments: [String]) -> Bool {
        arguments.dropFirst().contains { ["--export", "--list-models", "--list-sizes", "--help", "-h"].contains($0) }
    }

    // MARK: 引数の解釈

    public static func parse(arguments: [String]) throws -> CommandLineCommand {
        var values: [String: String] = [:]
        var flags: Set<String> = []
        var args = Array(arguments.dropFirst())
        let valueOptions: Set<String> = ["--export", "--output", "--model", "--orientation", "--color", "--variant", "--size", "--background"]
        let flagOptions: Set<String> = ["--fill", "--list-models", "--list-sizes", "--help", "-h"]

        while !args.isEmpty {
            var arg = args.removeFirst()
            var inline: String?
            if arg.hasPrefix("--"), let eq = arg.firstIndex(of: "=") {
                inline = String(arg[arg.index(after: eq)...])
                arg = String(arg[..<eq])
            }
            if flagOptions.contains(arg) {
                flags.insert(arg)
            } else if valueOptions.contains(arg) {
                guard let value = inline ?? (args.isEmpty ? nil : args.removeFirst()) else {
                    throw CommandLineError.usage("\(arg) には値が必要です")
                }
                values[arg] = value
            } else {
                throw CommandLineError.usage("不明なオプション: \(arg)")
            }
        }

        if flags.contains("--help") || flags.contains("-h") { return .help }
        if flags.contains("--list-models") { return .listModels }
        if flags.contains("--list-sizes") { return .listSizes }
        guard let shot = values["--export"], !shot.isEmpty else { throw CommandLineError.usage("--export <スクショ> が必要です") }

        var request = ExportRequest(screenshot: URL(fileURLWithPath: shot))
        request.output = values["--output"].map { URL(fileURLWithPath: $0) }
        request.model = values["--model"]
        request.color = values["--color"]
        request.variant = values["--variant"]
        request.fill = flags.contains("--fill")
        if let o = values["--orientation"] {
            guard let parsed = BezelOrientation(rawValue: o.lowercased()) else {
                throw CommandLineError.usage("--orientation は portrait か landscape です: \(o)")
            }
            request.orientation = parsed
        }
        if let s = values["--size"] { request.canvas = try parseSize(s) }
        if let b = values["--background"] { request.background = try parseBackground(b) }
        if let out = request.output, out.pathExtension.lowercased() != "png" {
            throw CommandLineError.usage("--output は .png のパスを指定してください: \(out.lastPathComponent)")
        }
        return .export(request)
    }

    public static func parseSize(_ text: String) throws -> ExportRequest.Canvas {
        let parts = text.lowercased().replacingOccurrences(of: "×", with: "x").split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0, w <= 16384, h <= 16384 else {
            throw CommandLineError.usage("--size は 幅x高さ（例: 1320x2868、各 16384 以下）で指定してください: \(text)")
        }
        return .init(width: w, height: h)
    }

    public static func parseBackground(_ text: String) throws -> BackgroundStyle {
        let lower = text.lowercased()
        if lower == "transparent" { return .transparent }
        if lower.hasPrefix("gradient:") {
            let parts = text.dropFirst("gradient:".count).split(separator: ",").map(String.init)
            guard parts.count == 2 || parts.count == 3 else {
                throw CommandLineError.usage("グラデーションは gradient:#RRGGBB,#RRGGBB[,角度] の形式です: \(text)")
            }
            var angle = 90.0
            if parts.count == 3 {
                guard let a = Double(parts[2]) else { throw CommandLineError.usage("グラデーションの角度が数値ではありません: \(parts[2])") }
                angle = a
            }
            return .gradient(start: try parseHexColor(parts[0]), end: try parseHexColor(parts[1]), angleDegrees: angle)
        }
        return .solid(try parseHexColor(text))
    }

    /// `#RRGGBB` / `RRGGBB` / `#RRGGBBAA`
    public static func parseHexColor(_ text: String) throws -> RGBAColor {
        var hex = text.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else {
            throw CommandLineError.usage("色は #RRGGBB（または #RRGGBBAA）で指定してください: \(text)")
        }
        let hasAlpha = hex.count == 8
        let shift: (Int) -> Double = { Double((value >> UInt64($0)) & 0xFF) / 255 }
        return hasAlpha
            ? RGBAColor(r: shift(24), g: shift(16), b: shift(8), a: shift(0))
            : RGBAColor(r: shift(16), g: shift(8), b: shift(0))
    }

    // MARK: 実行

    /// 書き出して出力パスを返す。ベゼルは `library` に登録済みのものから選ぶ。
    public static func run(_ request: ExportRequest, library: BezelLibrary,
                           currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                           warn: (String) -> Void = { _ in }) throws -> URL {
        let screenshot: CGImage
        do { screenshot = try ImageFile.load(url: request.screenshot) } catch {
            throw CommandLineError.failure("スクショを読み込めません: \(request.screenshot.path)")
        }

        let groups = BezelCatalog.groups(try library.list())
        guard !groups.isEmpty else { throw CommandLineError.failure("ベゼルが登録されていません。アプリでベゼルを取り込んでください") }
        let group = try selectGroup(request.model, from: groups)
        let selection = try selectBezel(in: group, request: request, screenshot: screenshot)
        let bezel = selection.resolved // その向きが未登録なら、登録されている逆向きを回した定義

        if AspectMatcher.matches(screenshotWidth: screenshot.width, screenshotHeight: screenshot.height, aperture: bezel.aperture) == false {
            warn("スクショの縦横比がベゼルの画面領域と合いません。余白が黒になります（\(bezel.modelName)）")
        }

        var bezelImage = try library.loadImage(for: selection.registered)
        if selection.isRotated { bezelImage = ImageRotation.rotate(bezelImage, selection.rotation) ?? bezelImage }
        let settings = ComposeSettings(background: request.background)
        let crop: ScreenCrop = request.fill ? .fill : .fit
        let canvas = request.canvas.map { resolvedCanvas($0, for: bezel) }

        let image: CGImage
        if let canvas {
            image = try Composer.composeFitted(screenshot: screenshot, bezel: bezel, bezelImage: bezelImage,
                                               settings: settings, crop: crop, canvas: (canvas.width, canvas.height))
        } else {
            image = try Composer.compose(screenshot: screenshot, bezel: bezel, bezelImage: bezelImage, settings: settings, crop: crop)
        }

        let output = request.output.map { $0.path.hasPrefix("/") ? $0 : currentDirectory.appendingPathComponent($0.path) }
            ?? currentDirectory.appendingPathComponent(defaultFileName(screenshot: request.screenshot, bezel: bezel, canvas: canvas))
        do { try ImageFile.writePNG(image, to: output) } catch {
            throw CommandLineError.failure("書き出せません（保存先のフォルダが無い、または書き込み不可）: \(output.path)")
        }
        return output
    }

    /// App Store の iPhone / iPad サイズ（縦横どちらの指定でも）なら、ベゼルの向きに合わせて縦横を決める。それ以外は指定どおり。
    static func resolvedCanvas(_ c: ExportRequest.Canvas, for bezel: Bezel) -> ExportRequest.Canvas {
        let match = AppStoreSize.all.first {
            ($0.family == .iPhone || $0.family == .iPad)
                && Set([$0.width, $0.height]) == Set([c.width, c.height]) && $0.width != $0.height
        }
        guard let match else { return c }
        let o = match.canvas(for: bezel.effectiveOrientation)
        return .init(width: o.width, height: o.height)
    }

    static func defaultFileName(screenshot: URL, bezel: Bezel, canvas: ExportRequest.Canvas?) -> String {
        let suffix = canvas.map { "_\($0.width)x\($0.height)" } ?? ""
        let raw = "\(screenshot.deletingPathExtension().lastPathComponent)_\(bezel.modelName)\(suffix).png"
        return raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    private static func selectGroup(_ name: String?, from groups: [BezelModelGroup]) throws -> BezelModelGroup {
        let list = groups.map(\.model).joined(separator: "、")
        guard let name, !name.isEmpty else {
            if groups.count == 1 { return groups[0] }
            throw CommandLineError.failure("--model が必要です。登録済みの機種: \(list)")
        }
        if let exact = groups.first(where: { $0.model.caseInsensitiveCompare(name) == .orderedSame }) { return exact }
        let partial = groups.filter { $0.model.range(of: name, options: .caseInsensitive) != nil }
        if partial.count == 1 { return partial[0] }
        if partial.isEmpty { throw CommandLineError.failure("機種「\(name)」が見つかりません。登録済みの機種: \(list)") }
        throw CommandLineError.failure("機種「\(name)」に複数が該当します: \(partial.map(\.model).joined(separator: "、"))")
    }

    private static func selectBezel(in group: BezelModelGroup, request: ExportRequest, screenshot: CGImage) throws -> BezelSelection {
        var variant: String?
        if let v = request.variant {
            guard let match = group.variants.first(where: { $0.caseInsensitiveCompare(v) == .orderedSame }) else {
                let have = group.variants.isEmpty ? "形態の区別なし" : group.variants.joined(separator: "、")
                throw CommandLineError.failure("形態「\(v)」がありません（\(have)）")
            }
            variant = match
        }
        var color: String?
        if let wanted = request.color {
            let available = request.orientation.map { group.selectableColors(for: $0, variant: variant) }
                ?? uniqued(BezelOrientation.allCases.flatMap { group.selectableColors(for: $0, variant: variant) })
            guard let match = available.first(where: { $0.caseInsensitiveCompare(wanted) == .orderedSame }) else {
                throw CommandLineError.failure("色「\(wanted)」がありません（\(available.isEmpty ? "色の区別なし" : available.joined(separator: "、"))）")
            }
            color = match
        }
        // 向きの指定がその機種に登録されていなければ、逆向きのベゼルを回して使う。向きが固定のデバイス（Mac など）は回せない
        if let o = request.orientation {
            if !group.allowsRotation, !group.orientations(variant: variant).contains(o) {
                let have = group.orientations(variant: variant).map(\.rawValue).joined(separator: "、")
                throw CommandLineError.failure("\(group.model) は向きが固定です（\(have)）")
            }
            return group.selection(orientation: o, color: color, variant: variant)
        }
        return group.bestSelection(screenshotWidth: screenshot.width, screenshotHeight: screenshot.height, color: color, variant: variant)
    }

    private static func uniqued(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    // MARK: エントリポイント

    /// 引数を解釈して実行し、終了コードを返す。`out` は標準出力、`err` は標準エラー。
    public static func runCommandLine(arguments: [String], library: BezelLibrary = BezelLibrary(),
                                      out: (String) -> Void, err: (String) -> Void) -> Int32 {
        do {
            switch try parse(arguments: arguments) {
            case .help:
                out(usage)
            case .listModels:
                let groups = BezelCatalog.groups(try library.list())
                if groups.isEmpty { err("ベゼルが登録されていません") }
                for g in groups {
                    let o = g.orientations.map(\.rawValue).joined(separator: "/")
                    let colors = uniqued(g.orientations.flatMap { g.colors(for: $0) })
                    let variants = g.variants.isEmpty ? "" : "\t形態: " + g.variants.joined(separator: ", ")
                    out("\(g.model)\t向き: \(o)\t色: \(colors.isEmpty ? "-" : colors.joined(separator: ", "))\(variants)")
                }
            case .listSizes:
                for s in AppStoreSize.all {
                    out("\(s.width)x\(s.height)\t\(s.family.rawValue) \(s.label)\(s.isRequired ? "\t(必須)" : "")")
                }
            case .export(let request):
                out(try run(request, library: library, warn: { err("警告: \($0)") }).path)
            }
            return 0
        } catch let e as CommandLineError {
            err("エラー: \(e.localizedDescription)")
            if case .usage = e { err("--help で使い方を表示します"); return 2 }
            return 1
        } catch {
            err("エラー: \(error.localizedDescription)")
            return 1
        }
    }
}
