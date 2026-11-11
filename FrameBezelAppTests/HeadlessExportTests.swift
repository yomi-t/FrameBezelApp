import Testing
import Foundation
import CoreGraphics
@testable import FrameBezelApp

struct HeadlessParseTests {
    private func parse(_ args: String...) throws -> CommandLineCommand {
        try HeadlessExport.parse(arguments: ["app"] + args)
    }
    private func request(_ args: String...) throws -> ExportRequest {
        guard case .export(let r) = try HeadlessExport.parse(arguments: ["app"] + args) else { throw CommandLineError.usage("not export") }
        return r
    }

    @Test func detectsCommandLineInvocation() {
        #expect(HeadlessExport.isCommandLineInvocation(["app", "--export", "a.png"]))
        #expect(HeadlessExport.isCommandLineInvocation(["app", "--list-models"]))
        #expect(HeadlessExport.isCommandLineInvocation(["app", "--help"]))
        #expect(!HeadlessExport.isCommandLineInvocation(["app"]))
        #expect(!HeadlessExport.isCommandLineInvocation(["app", "-NSDocumentRevisionsDebugMode", "YES"]))
        #expect(!HeadlessExport.isCommandLineInvocation(["--export"])) // 先頭は実行ファイル名
    }

    @Test func parsesAllOptions() throws {
        let r = try request("--export", "/a/shot.png", "--output", "/o/out.png", "--model", "iPhone 18 Pro",
                            "--orientation", "Landscape", "--color", "Black", "--size", "1320x2868", "--fill",
                            "--background", "#FF0000")
        #expect(r.screenshot.path == "/a/shot.png" && r.output?.path == "/o/out.png")
        #expect(r.model == "iPhone 18 Pro" && r.color == "Black" && r.orientation == .landscape)
        #expect(r.canvas == .init(width: 1320, height: 2868) && r.fill)
        #expect(r.background == .solid(RGBAColor(r: 1, g: 0, b: 0)))
    }

    @Test func defaultsAreFitTransparentAndOriginalSize() throws {
        let r = try request("--export", "a.png")
        #expect(!r.fill && r.background == .transparent && r.canvas == nil && r.output == nil && r.model == nil)
    }

    @Test func acceptsEqualsSyntax() throws {
        let r = try request("--export=a.png", "--size=1179x2556", "--model=X")
        #expect(r.screenshot.lastPathComponent == "a.png" && r.canvas?.width == 1179 && r.model == "X")
    }

    @Test func helpAndListsNeedNoExport() throws {
        #expect(try parse("--help") == .help)
        #expect(try parse("-h") == .help)
        #expect(try parse("--list-models") == .listModels)
        #expect(try parse("--list-sizes") == .listSizes)
    }

    @Test func rejectsBadUsage() {
        #expect(throws: CommandLineError.self) { try parse("--output", "x.png") }              // --export なし
        #expect(throws: CommandLineError.self) { try parse("--export") }                       // 値なし
        #expect(throws: CommandLineError.self) { try parse("--export", "a.png", "--bogus") }   // 不明
        #expect(throws: CommandLineError.self) { try parse("--export", "a.png", "--orientation", "diagonal") }
        #expect(throws: CommandLineError.self) { try parse("--export", "a.png", "--output", "out.jpg") }
        #expect(throws: CommandLineError.self) { try parse("--export", "a.png", "--size", "big") }
    }

    @Test func sizeParsing() throws {
        #expect(try HeadlessExport.parseSize("1320x2868") == .init(width: 1320, height: 2868))
        #expect(try HeadlessExport.parseSize("1320X2868") == .init(width: 1320, height: 2868))
        #expect(try HeadlessExport.parseSize("1320×2868") == .init(width: 1320, height: 2868))
        for bad in ["", "0x10", "10x0", "-1x5", "10", "10x", "axb", "1x2x3", "99999x10"] {
            #expect(throws: CommandLineError.self, "\(bad)") { try HeadlessExport.parseSize(bad) }
        }
    }

    @Test func colorParsing() throws {
        #expect(try HeadlessExport.parseHexColor("#000000") == RGBAColor(r: 0, g: 0, b: 0))
        #expect(try HeadlessExport.parseHexColor("ffffff") == RGBAColor(r: 1, g: 1, b: 1))
        let c = try HeadlessExport.parseHexColor("#FF000080")
        #expect(c.r == 1 && abs(c.a - 128.0 / 255) < 1e-9)
        for bad in ["", "#12345", "#GGGGGG", "red", "#1234567"] {
            #expect(throws: CommandLineError.self, "\(bad)") { try HeadlessExport.parseHexColor(bad) }
        }
    }

    @Test func backgroundParsing() throws {
        #expect(try HeadlessExport.parseBackground("Transparent") == .transparent)
        #expect(try HeadlessExport.parseBackground("#112233") == .solid(try HeadlessExport.parseHexColor("#112233")))
        let g = try HeadlessExport.parseBackground("gradient:#FF0000,#0000FF")
        #expect(g == .gradient(start: RGBAColor(r: 1, g: 0, b: 0), end: RGBAColor(r: 0, g: 0, b: 1), angleDegrees: 90))
        if case .gradient(_, _, let a) = try HeadlessExport.parseBackground("gradient:#000000,#ffffff,0") { #expect(a == 0) } else { Issue.record("gradient") }
        #expect(throws: CommandLineError.self) { try HeadlessExport.parseBackground("gradient:#000000") }
        #expect(throws: CommandLineError.self) { try HeadlessExport.parseBackground("gradient:#000000,#ffffff,x") }
        #expect(throws: CommandLineError.self) { try HeadlessExport.parseBackground("blue") }
    }

    @Test func usageErrorsExitWithTwoAndFailuresWithOne() throws {
        var out: [String] = [], err: [String] = []
        let lib = BezelLibrary(appDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("hl-\(UUID().uuidString)"))
        #expect(HeadlessExport.runCommandLine(arguments: ["app", "--export"], library: lib, out: { out.append($0) }, err: { err.append($0) }) == 2)
        #expect(HeadlessExport.runCommandLine(arguments: ["app", "--help"], library: lib, out: { out.append($0) }, err: { err.append($0) }) == 0)
        #expect(out.last?.contains("--export") == true)
        // 画像が無い → 実行時の失敗は 1
        #expect(HeadlessExport.runCommandLine(arguments: ["app", "--export", "/nonexistent.png"], library: lib, out: { out.append($0) }, err: { err.append($0) }) == 1)
        #expect(err.contains { $0.contains("読み込めません") })
    }

    @Test func listSizesPrintsEveryOfficialSizeWithRequiredMark() {
        var out: [String] = []
        let lib = BezelLibrary(appDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("hl-\(UUID().uuidString)"))
        #expect(HeadlessExport.runCommandLine(arguments: ["app", "--list-sizes"], library: lib, out: { out.append($0) }, err: { _ in }) == 0)
        #expect(out.count == AppStoreSize.all.count)
        #expect(out.filter { $0.contains("(必須)") }.count == 2)
        #expect(out.contains { $0.hasPrefix("1179x2556") })
    }
}

struct HeadlessRunTests {
    private struct Env {
        let root: URL
        let library: BezelLibrary
        init(bezels: [(String, Int, Int, CGRect)] = [
            ("iPhone X - Black - Portrait.png", 100, 200, CGRect(x: 20, y: 20, width: 60, height: 160)),
            ("iPhone X - White - Portrait.png", 100, 200, CGRect(x: 20, y: 20, width: 60, height: 160)),
            ("iPhone X - Black - Landscape.png", 200, 100, CGRect(x: 20, y: 20, width: 160, height: 60)),
            ("iPad Y - Gray - Portrait.png", 150, 200, CGRect(x: 15, y: 20, width: 120, height: 160)),
        ]) throws {
            root = try TestSupport.makeTempDirectory()
            library = BezelLibrary(appDirectory: root.appendingPathComponent("app"))
            let src = root.appendingPathComponent("src")
            try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
            for (n, w, h, s) in bezels {
                let u = src.appendingPathComponent(n)
                try TestSupport.writeBezelPNG(to: u, width: w, height: h, screen: s)
                try library.add(pngURL: u, meta: BezelNaming.parse(fileName: n, folderName: nil))
            }
        }
        func shot(_ w: Int, _ h: Int, name: String = "shot.png") throws -> URL {
            let u = root.appendingPathComponent(name)
            try ImageFile.writePNG(TestSupport.solid(w, h), to: u)
            return u
        }
        func out(_ name: String = "out.png") -> URL { root.appendingPathComponent(name) }
        func cleanup() { TestSupport.remove(root) }
    }

    private func run(_ env: Env, _ r: ExportRequest, warn: @escaping (String) -> Void = { _ in }) throws -> CGImage {
        let url = try HeadlessExport.run(r, library: env.library, currentDirectory: env.root, warn: warn)
        return try ImageFile.load(url: url)
    }

    @Test func exportsAtBezelSizeWithTransparency() throws {
        let env = try Env(); defer { env.cleanup() }
        var r = ExportRequest(screenshot: try env.shot(60, 160)); r.model = "iPhone X"; r.output = env.out()
        let image = try run(env, r)
        #expect(image.width == 100 && image.height == 200)
        #expect(TestSupport.pixel(image, 50, 100) == .init(r: 255, g: 0, b: 0, a: 255))
    }

    @Test func choosesOrientationFromScreenshotAspect() throws {
        let env = try Env(); defer { env.cleanup() }
        var r = ExportRequest(screenshot: try env.shot(160, 60)); r.model = "iphone x"; r.output = env.out() // 大文字小文字は区別しない
        let image = try run(env, r)
        #expect(image.width == 200 && image.height == 100)
    }

    @Test func explicitOrientationAndColorAreHonored() throws {
        let env = try Env(); defer { env.cleanup() }
        var r = ExportRequest(screenshot: try env.shot(60, 160)); r.model = "iPhone X"; r.orientation = .landscape; r.output = env.out()
        #expect(try run(env, r).width == 200)
        r.orientation = .portrait; r.color = "white"
        #expect(try run(env, r).width == 100)
    }

    @Test func appStoreSizeFollowsBezelOrientationRegardlessOfGivenOrder() throws {
        let env = try Env(); defer { env.cleanup() }
        var r = ExportRequest(screenshot: try env.shot(60, 160)); r.model = "iPhone X"; r.output = env.out()
        r.canvas = .init(width: 2868, height: 1320) // 横指定でも、縦のベゼルなら縦長になる
        let portrait = try run(env, r)
        #expect(portrait.width == 1320 && portrait.height == 2868)
        r.screenshot = try env.shot(160, 60, name: "wide.png")
        let landscape = try run(env, r)
        #expect(landscape.width == 2868 && landscape.height == 1320)
    }

    @Test func customSizeIsUsedLiterallyAndIsOpaque() throws {
        let env = try Env(); defer { env.cleanup() }
        var r = ExportRequest(screenshot: try env.shot(60, 160)); r.model = "iPhone X"; r.output = env.out()
        r.canvas = .init(width: 500, height: 300)
        let image = try run(env, r)
        #expect(image.width == 500 && image.height == 300)
        #expect(TestSupport.pixel(image, 2, 2) == .init(r: 255, g: 255, b: 255, a: 255)) // 透明背景の余白は白
        let bytes = try Data(contentsOf: env.out())
        #expect(bytes[25] == 2) // RGB（アルファ無し）
    }

    @Test func backgroundColorFillsMargins() throws {
        let env = try Env(); defer { env.cleanup() }
        var r = ExportRequest(screenshot: try env.shot(60, 160)); r.model = "iPhone X"; r.output = env.out()
        r.canvas = .init(width: 1000, height: 1000); r.background = .solid(RGBAColor(r: 0, g: 0, b: 1))
        #expect(TestSupport.pixel(try run(env, r), 10, 500) == .init(r: 0, g: 0, b: 255, a: 255))
    }

    @Test func fillDiffersFromFitForMismatchedAspect() throws {
        let env = try Env(); defer { env.cleanup() }
        var r = ExportRequest(screenshot: try env.shot(120, 80)); r.model = "iPad Y"; r.output = env.out()
        r.orientation = .portrait // 向きを省略すると、登録の無い横向きを回転して合わせる
        var warnings: [String] = []
        let fit = try run(env, r, warn: { warnings.append($0) })
        #expect(TestSupport.pixel(fit, 75, 30).r == 0 && TestSupport.pixel(fit, 75, 30).a == 255) // 上の黒帯
        #expect(warnings.count == 1)
        r.fill = true
        let fill = try run(env, r)
        #expect(TestSupport.pixel(fill, 75, 30) == .init(r: 255, g: 0, b: 0, a: 255))
    }

    @Test func defaultOutputGoesToCurrentDirectoryWithDerivedName() throws {
        let env = try Env(); defer { env.cleanup() }
        var r = ExportRequest(screenshot: try env.shot(60, 160, name: "My Shot.png")); r.model = "iPhone X"; r.color = "Black"
        let url = try HeadlessExport.run(r, library: env.library, currentDirectory: env.root)
        #expect(url.deletingLastPathComponent().path == env.root.path)
        #expect(url.lastPathComponent == "My Shot_iPhone X.png")
        r.canvas = .init(width: 1179, height: 2556)
        #expect(try HeadlessExport.run(r, library: env.library, currentDirectory: env.root).lastPathComponent == "My Shot_iPhone X_1179x2556.png")
    }

    @Test func relativeOutputResolvesAgainstCurrentDirectory() throws {
        let env = try Env(); defer { env.cleanup() }
        var r = ExportRequest(screenshot: try env.shot(60, 160)); r.model = "iPhone X"; r.output = URL(fileURLWithPath: "rel.png", relativeTo: nil)
        r.output = URL(string: "rel.png")
        let url = try HeadlessExport.run(r, library: env.library, currentDirectory: env.root)
        #expect(url.path == env.root.appendingPathComponent("rel.png").path)
    }

    @Test func overwritesExistingOutput() throws {
        let env = try Env(); defer { env.cleanup() }
        try Data("old".utf8).write(to: env.out())
        var r = ExportRequest(screenshot: try env.shot(60, 160)); r.model = "iPhone X"; r.output = env.out()
        #expect(try run(env, r).width == 100)
    }

    @Test func modelSelectionRules() throws {
        let env = try Env(); defer { env.cleanup() }
        var r = ExportRequest(screenshot: try env.shot(60, 160)); r.output = env.out()
        // 複数機種で --model 省略 → 失敗し、候補を示す
        do { _ = try run(env, r); Issue.record("should fail") } catch let e as CommandLineError {
            #expect(e.localizedDescription.contains("iPad Y") && e.localizedDescription.contains("iPhone X"))
        }
        r.model = "pad"           // 部分一致（1 件）
        #expect(try run(env, r).width == 150)
        r.model = "i"             // 部分一致が複数
        #expect(throws: CommandLineError.self) { try run(env, r) }
        r.model = "Nokia"
        #expect(throws: CommandLineError.self) { try run(env, r) }
    }

    @Test func singleRegisteredModelNeedsNoModelOption() throws {
        let env = try Env(bezels: [("Only - Black - Portrait.png", 100, 200, CGRect(x: 20, y: 20, width: 60, height: 160))])
        defer { env.cleanup() }
        let r = ExportRequest(screenshot: try env.shot(60, 160), output: env.out())
        #expect(try run(env, r).width == 100)
    }

    @Test func unavailableColorFailsAndUnavailableOrientationIsRotated() throws {
        let env = try Env(); defer { env.cleanup() }
        var r = ExportRequest(screenshot: try env.shot(60, 160)); r.output = env.out(); r.model = "iPad Y"
        // iPad Y は縦だけ登録。横を指定すると、縦のベゼルを回転して使う
        r.orientation = .landscape
        let rotated = try run(env, r)
        #expect(rotated.width == 200 && rotated.height == 150)
        r.orientation = nil; r.color = "Pink"
        do { _ = try run(env, r); Issue.record("should fail") } catch let e as CommandLineError {
            #expect(e.localizedDescription.contains("Gray"))
        }
        // 回転して使う向きでは、回転元の色を指定できる
        r.color = "Gray"; r.orientation = .landscape
        #expect(try run(env, r).width == 200)
        // 横が登録されている iPhone X では、横にある色（Black）だけ。White は縦にしか無い
        r.model = "iPhone X"; r.color = "White"; r.orientation = .landscape
        #expect(throws: CommandLineError.self) { try run(env, r) }
        r.color = "White"; r.orientation = .portrait
        #expect(try run(env, r).width == 100)
    }

    @Test func fixedOrientationDevicesRejectAnotherOrientationAndIgnorePortraitScreenshots() throws {
        let env = try Env(bezels: [("MacBook Neo - Blush.png", 200, 120, CGRect(x: 20, y: 20, width: 160, height: 80))])
        defer { env.cleanup() }
        var r = ExportRequest(screenshot: try env.shot(80, 160)); r.output = env.out()
        #expect(try run(env, r).width == 200) // 縦長のスクショでも Mac は回さない
        r.orientation = .portrait
        do { _ = try run(env, r); Issue.record("should fail") } catch let e as CommandLineError {
            #expect(e.localizedDescription.contains("向きが固定"))
        }
        r.orientation = .landscape
        #expect(try run(env, r).width == 200)
    }

    @Test func emptyLibraryAndMissingFilesFail() throws {
        let env = try Env(bezels: []); defer { env.cleanup() }
        let r = ExportRequest(screenshot: try env.shot(60, 160), output: env.out())
        #expect(throws: CommandLineError.self) { try run(env, r) }

        let ok = try Env(); defer { ok.cleanup() }
        let missing = ExportRequest(screenshot: ok.root.appendingPathComponent("none.png"), output: ok.out(), model: "iPad Y")
        #expect(throws: CommandLineError.self) { try run(ok, missing) }
        var badDir = ExportRequest(screenshot: try ok.shot(60, 160), output: URL(fileURLWithPath: "/nonexistent-dir/x.png")); badDir.model = "iPad Y"
        #expect(throws: CommandLineError.self) { try run(ok, badDir) }
    }

    @Test func exportsDuoByVariantAndOrientation() throws {
        let env = try Env(bezels: [
            ("iPhone Duo - Night Sky - Inner Open Portrait.png", 100, 130, CGRect(x: 10, y: 10, width: 80, height: 110)),
            ("iPhone Duo - Night Sky - Outer Closed Portrait.png", 80, 120, CGRect(x: 10, y: 10, width: 60, height: 100)),
            ("iPhone Duo - Night Sky - Outer Open.png", 200, 120, CGRect(x: 110, y: 10, width: 80, height: 100)),
        ])
        defer { env.cleanup() }
        var r = ExportRequest(screenshot: try env.shot(60, 100)); r.output = env.out()
        #expect(try run(env, r).width == 100) // 既定は先頭の形態（Inner Open）
        r.variant = "outer closed"             // 大文字小文字は区別しない
        #expect(try run(env, r).width == 80)
        r.variant = "Outer Open"
        #expect(try run(env, r).width == 200)
        r.variant = "Tent"
        #expect(throws: CommandLineError.self) { try run(env, r) }
        r.variant = "Outer Open"; r.orientation = .landscape // 開いた外側（画面は縦長）の横は未登録 → 回転して使う
        let rotated = try run(env, r)
        #expect(rotated.width == 120 && rotated.height == 200)
    }

    @Test func variantOptionIsParsedAndListed() throws {
        guard case .export(let r) = try HeadlessExport.parse(arguments: ["app", "--export", "a.png", "--variant", "Inner Open"]) else {
            Issue.record("export expected"); return
        }
        #expect(r.variant == "Inner Open")
        let env = try Env(bezels: [("iPhone Duo - Night Sky - Inner Open Portrait.png", 100, 130, CGRect(x: 10, y: 10, width: 80, height: 110)),
                                   ("iPhone Duo - Night Sky - Outer Open.png", 200, 120, CGRect(x: 110, y: 10, width: 80, height: 100))])
        defer { env.cleanup() }
        var out: [String] = []
        _ = HeadlessExport.runCommandLine(arguments: ["app", "--list-models"], library: env.library, out: { out.append($0) }, err: { _ in })
        #expect(out.first?.contains("形態: Inner Open, Outer Open") == true)
        #expect(out.first?.contains("Night Sky") == true && out.first?.contains("Night Sky Inner") == false)
    }

    @Test func listModelsShowsOrientationsAndColors() throws {
        let env = try Env(); defer { env.cleanup() }
        var out: [String] = []
        #expect(HeadlessExport.runCommandLine(arguments: ["app", "--list-models"], library: env.library, out: { out.append($0) }, err: { _ in }) == 0)
        let phone = try #require(out.first { $0.hasPrefix("iPhone X") })
        #expect(phone.contains("portrait/landscape") && phone.contains("Black") && phone.contains("White"))
        #expect(out.contains { $0.hasPrefix("iPad Y") && $0.contains("Gray") })
    }

    @Test func fullCommandLineRoundTrip() throws {
        let env = try Env(); defer { env.cleanup() }
        let shot = try env.shot(60, 160)
        var out: [String] = [], err: [String] = []
        let code = HeadlessExport.runCommandLine(
            arguments: ["app", "--export", shot.path, "--model", "iPhone X", "--size", "1179x2556",
                        "--background", "gradient:#FF0000,#0000FF,0", "--output", env.out().path],
            library: env.library, out: { out.append($0) }, err: { err.append($0) })
        #expect(code == 0 && out == [env.out().path])
        let image = try ImageFile.load(url: env.out())
        #expect(image.width == 1179 && image.height == 2556)
    }
}
