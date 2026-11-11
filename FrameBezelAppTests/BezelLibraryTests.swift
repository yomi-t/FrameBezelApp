import Testing
import Foundation
import CoreGraphics
@testable import FrameBezelApp

struct BezelLibraryTests {
    /// テストごとの隔離環境（ライブラリ + ダウンロード元の PNG を置く作業フォルダ）。
    private struct Sandbox {
        let root: URL
        let library: BezelLibrary
        var source: URL { root.appendingPathComponent("src", isDirectory: true) }

        init() throws {
            root = try TestSupport.makeTempDirectory()
            library = BezelLibrary(appDirectory: root.appendingPathComponent("app", isDirectory: true))
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        }

        func png(_ name: String, in dir: URL? = nil, width: Int = 100, height: Int = 200, screen: CGRect? = nil) throws -> URL {
            let dir = dir ?? source
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            try TestSupport.writeBezelPNG(to: url, width: width, height: height,
                                          screen: screen ?? CGRect(x: 20, y: 20, width: width - 40, height: height - 40))
            return url
        }

        func cleanup() { TestSupport.remove(root) }
    }

    // MARK: 単体追加

    @Test func addCopiesDetectsAndWritesJSON() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let url = try sb.png("Bezel-iPhone-17.png")
        let bezel = try sb.library.add(pngURL: url)
        #expect(bezel.name == "iPhone 17")
        #expect(bezel.imageWidth == 100 && bezel.imageHeight == 200)
        #expect(bezel.aperture.width == 60 && bezel.aperture.height == 160)
        #expect(FileManager.default.fileExists(atPath: sb.library.imageURL(for: bezel).path))
        #expect(try sb.library.list() == [bezel])
        // 元ファイルは残る
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func addReadsAppleStyleFileNameMetadata() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let bezel = try sb.library.add(pngURL: try sb.png("iPhone 18 Pro - Black - Landscape.png"))
        #expect(bezel.model == "iPhone 18 Pro" && bezel.color == "Black" && bezel.orientation == .landscape)
        #expect(bezel.name == "iPhone 18 Pro") // 名前は機種の正式名称だけ（色は別項目）
    }

    @Test func addUsesGivenNameOverDerivedOne() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let bezel = try sb.library.add(pngURL: try sb.png("a.png"), name: "Custom")
        #expect(bezel.name == "Custom")
    }

    @Test func addRejectsNonPNG() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let txt = sb.source.appendingPathComponent("a.jpg")
        try Data().write(to: txt)
        #expect(throws: BezelLibraryError.self) { try sb.library.add(pngURL: txt) }
    }

    @Test func addWithoutWindowFailsAndLeavesNoCopy() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let url = sb.source.appendingPathComponent("solid.png")
        try ImageFile.writePNG(TestSupport.solid(50, 50), to: url)
        #expect(throws: BezelDetectorError.self) { try sb.library.add(pngURL: url) }
        #expect(try sb.library.list().isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: sb.library.bezelsDirectory.path)
        #expect(files.isEmpty)
    }

    @Test func addingSameFileNameTwiceGetsUniqueName() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let url = try sb.png("same.png")
        let a = try sb.library.add(pngURL: url), b = try sb.library.add(pngURL: url)
        #expect(a.bezelFile == "same.png" && b.bezelFile == "same-2.png")
        #expect(try sb.library.list().count == 2)
    }

    // MARK: 一覧・更新・削除

    @Test func listIsSortedNaturally() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        for n in ["Bezel-iPhone-10.png", "Bezel-iPhone-2.png", "Bezel-iPad-1.png"] { try sb.library.add(pngURL: try sb.png(n)) }
        #expect(try sb.library.list().map(\.name) == ["iPad 1", "iPhone 2", "iPhone 10"])
    }

    @Test func listSkipsDefinitionsWithoutPNGAndBrokenJSON() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let b = try sb.library.add(pngURL: try sb.png("ok.png"))
        let dir = sb.library.bezelsDirectory
        try b.write(to: dir.appendingPathComponent("orphan.json")) // bezelFile は ok.png だが orphan.json 自体は有効
        var orphan = b; orphan.bezelFile = "missing.png"
        try orphan.write(to: dir.appendingPathComponent("missing.json"))
        try Data("{ broken".utf8).write(to: dir.appendingPathComponent("broken.json"))
        let names = try sb.library.list().map(\.bezelFile)
        #expect(!names.contains("missing.png"))
        #expect(names.filter { $0 == "ok.png" }.count == 2) // orphan.json も ok.png を指す有効な定義
    }

    @Test func updatePersistsChanges() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        var b = try sb.library.add(pngURL: try sb.png("a.png"))
        b.name = "Renamed"
        b.aperture.x += 3
        try sb.library.update(b)
        #expect(try sb.library.list().first == b)
    }

    @Test func updateOfMissingImageThrowsNotFound() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let ghost = TestSupport.bezel(file: "ghost.png")
        #expect(throws: BezelLibraryError.self) { try sb.library.update(ghost) }
    }

    @Test func deleteRemovesImageAndJSON() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let b = try sb.library.add(pngURL: try sb.png("a.png"))
        try sb.library.delete(b)
        #expect(try sb.library.list().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: sb.library.bezelsDirectory.path).isEmpty)
    }

    @Test func loadImageReturnsStoredPNG() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let b = try sb.library.add(pngURL: try sb.png("a.png"))
        let image = try sb.library.loadImage(for: b)
        #expect(image.width == 100 && image.height == 200)
    }

    @Test func libraryDirectoryUsesAppName() {
        #expect(BezelLibrary.appDirectoryName == "FrameApp")
        let lib = BezelLibrary()
        #expect(lib.appDirectory.lastPathComponent == "FrameApp")
        #expect(lib.bezelsDirectory.lastPathComponent == "Bezels")
    }

    @Test func defaultNameFormatting() {
        #expect(BezelLibrary.defaultName(for: "Bezel-iPhone-17.png") == "iPhone 17")
        #expect(BezelLibrary.defaultName(for: "my_frame-x.png") == "my frame x")
        #expect(BezelLibrary.defaultName(for: "plain.png") == "plain")
    }

    // MARK: フォルダ取り込み

    @Test func importFolderWithOrientationSubfoldersUsesParentAsModel() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let model = sb.source.appendingPathComponent("iPad Air", isDirectory: true)
        _ = try sb.png("iPad Air - Gray - Portrait.png", in: model.appendingPathComponent("Portrait"))
        _ = try sb.png("iPad Air - Gray - Landscape.png", in: model.appendingPathComponent("Landscape"),
                       width: 200, height: 100, screen: CGRect(x: 20, y: 20, width: 160, height: 60))
        let r = sb.library.importFolder(model)
        #expect(r.added.count == 2 && r.failed.isEmpty)
        #expect(Set(r.added.map(\.model)) == ["iPad Air"])
        #expect(Set(r.added.compactMap(\.orientation)) == [.portrait, .landscape])
    }

    @Test func importParentFolderWithSeveralModels() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        _ = try sb.png("A - Black - Portrait.png", in: sb.source.appendingPathComponent("A"))
        _ = try sb.png("B - White - Portrait.png", in: sb.source.appendingPathComponent("B"))
        let r = sb.library.importFolder(sb.source)
        #expect(r.added.count == 2)
        #expect(BezelCatalog.groups(try sb.library.list()).map(\.model).sorted() == ["A", "B"])
    }

    @Test func importFillsOrientationFromWindowShapeWhenNameHasNone() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let folder = sb.source.appendingPathComponent("Mac")
        _ = try sb.png("Mac - Silver.png", in: folder, width: 200, height: 100, screen: CGRect(x: 20, y: 20, width: 160, height: 60))
        let r = sb.library.importFolder(folder)
        #expect(r.added.first?.orientation == .landscape)
        // 推定後の再取り込みも重複として扱う
        #expect(sb.library.importFolder(folder).skippedDuplicates == 1)
        #expect(try sb.library.list().count == 1)
    }

    @Test func importIgnoresNonPNGAndReportsEmptyFolders() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let folder = sb.source.appendingPathComponent("Empty")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("readme.txt"))
        let r = sb.library.importFolder(folder)
        #expect(r.added.isEmpty && r.emptyFolders == ["Empty"])
    }

    @Test func importReportsFilesThatCannotBeDetected() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let folder = sb.source.appendingPathComponent("M")
        _ = try sb.png("M - Black - Portrait.png", in: folder)
        try ImageFile.writePNG(TestSupport.solid(40, 40), to: folder.appendingPathComponent("M - Red - Portrait.png"))
        try Data("not png".utf8).write(to: folder.appendingPathComponent("M - Blue - Portrait.png"))
        let r = sb.library.importFolder(folder)
        #expect(r.added.count == 1)
        #expect(r.failed.count == 2)
        #expect(try sb.library.list().count == 1) // 失敗したものはコピーが残らない
        #expect(try FileManager.default.contentsOfDirectory(atPath: sb.library.bezelsDirectory.path).count == 2) // PNG + JSON
    }

    @Test func importSkipsHiddenFiles() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let folder = sb.source.appendingPathComponent("M")
        _ = try sb.png(".hidden - Black - Portrait.png", in: folder)
        let r = sb.library.importFolder(folder)
        #expect(r.added.isEmpty && r.emptyFolders == ["M"])
    }

    @Test func importOfMissingFolderReportsFailureOrEmpty() {
        let lib = BezelLibrary(appDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("x-\(UUID().uuidString)"))
        let r = lib.importFolder(URL(fileURLWithPath: "/nonexistent-folder-\(UUID().uuidString)"))
        #expect(r.added.isEmpty)
        #expect(!r.failed.isEmpty || !r.emptyFolders.isEmpty)
    }

    @Test func importDeduplicatesByModelColorOrientationAcrossDifferentFileNames() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let a = sb.source.appendingPathComponent("M")
        _ = try sb.png("M - Black - Portrait.png", in: a)
        _ = sb.library.importFolder(a)
        let b = sb.root.appendingPathComponent("other/M")
        _ = try sb.png("M - Black - Portrait.png", in: b)
        let r = sb.library.importFolder(b)
        #expect(r.added.isEmpty && r.skippedDuplicates == 1)
    }

    @Test func importsDmgStyleFolderWherePNGsSitDirectlyUnderPNG() throws {
        // iPad / Mac の dmg: PNG/ の直下にファイルが並ぶ（機種フォルダが無い）
        let sb = try Sandbox(); defer { sb.cleanup() }
        let png = sb.source.appendingPathComponent("Bezel-iPad-(A16)/PNG")
        for n in ["iPad (A16) - Blue - Portrait.png", "iPad (A16) - Blue - Landscape.png", "iPad (A16) - Pink - Portrait.png"] {
            _ = try sb.png(n, in: png)
        }
        let r = sb.library.importFolder(sb.source)
        #expect(r.added.count == 3 && r.failed.isEmpty)
        let group = try #require(BezelCatalog.groups(try sb.library.list()).first)
        #expect(group.model == "iPad (A16)")
        #expect(group.colors(for: .portrait).sorted() == ["Blue", "Pink"])
    }

    @Test func importsMacFilesWithoutDashesAndInfersOrientation() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let png = sb.source.appendingPathComponent("Bezel-MacBook-Air-M5/PNG")
        for n in ["MacBook Air M5 13-inch Midnight.png", "MacBook Air M5 13-inch Silver.png", "MacBook Air M5 15-inch Silver.png"] {
            _ = try sb.png(n, in: png, width: 200, height: 100, screen: CGRect(x: 20, y: 20, width: 160, height: 60))
        }
        let r = sb.library.importFolder(sb.source)
        #expect(r.added.count == 3)
        let groups = BezelCatalog.groups(try sb.library.list())
        #expect(Set(groups.map(\.model)) == ["MacBook Air M5 13-inch", "MacBook Air M5 15-inch"])
        #expect(r.added.allSatisfy { $0.orientation == .landscape })
    }

    @Test func importsWatchFilesFromBandSubfoldersAsSizeSpecificModels() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let root = sb.source.appendingPathComponent("Bezel-Apple-Watch-Series-11-2025/PNG")
        _ = try sb.png("Apple Watch S11 - 42mm - Aluminum Silver + Sport Band Black.png", in: root.appendingPathComponent("Sport Band"))
        _ = try sb.png("Apple Watch S11 - 46mm - Aluminum Silver + Sport Band Black.png", in: root.appendingPathComponent("Sport Band"))
        _ = try sb.png("Apple Watch S11 - 42mm - Titanium Gold + Milanese Loop.png", in: root.appendingPathComponent("Milanese Loop"))
        let r = sb.library.importFolder(sb.source)
        #expect(r.added.count == 3)
        let groups = BezelCatalog.groups(try sb.library.list())
        #expect(Set(groups.map(\.model)) == ["Apple Watch S11 42mm", "Apple Watch S11 46mm"])
        #expect(groups.first { $0.model == "Apple Watch S11 42mm" }?.bezels.count == 2)
    }

    @Test func importsDuoFormsAsVariantsWithoutCollisions() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let png = sb.source.appendingPathComponent("iPhone Duo/PNG")
        let names = ["iPhone Duo - Night Sky - Inner Open Portrait.png", "iPhone Duo - Night Sky - Inner Open Landscape.png",
                     "iPhone Duo - Night Sky - Outer Closed Portrait.png", "iPhone Duo - Night Sky - Outer Closed Landscape.png",
                     "iPhone Duo - Night Sky - Outer Open.png", "iPhone Duo - Star White - Outer Open.png"]
        for n in names { _ = try sb.png(n, in: png) }
        let r = sb.library.importFolder(sb.source)
        #expect(r.added.count == 6 && r.skippedDuplicates == 0)
        #expect(Set(r.added.compactMap(\.color)) == ["Night Sky", "Star White"]) // 形態は色に混ざらない
        #expect(Set(r.added.compactMap(\.variant)) == ["Inner Open", "Outer Closed", "Outer Open"])
        let g = try #require(BezelCatalog.groups(try sb.library.list()).first)
        #expect(g.variants == ["Inner Open", "Outer Closed", "Outer Open"])
        // 再取り込みは全て重複
        #expect(sb.library.importFolder(sb.source).skippedDuplicates == 6)
    }

    @Test func importsIPhone11StyleFilesWithOnlyModelAndOrientation() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let png = sb.source.appendingPathComponent("Bezel-iPhone-11/PNG")
        for n in ["iPhone 11 - Portrait.png", "iPhone 11 Pro - Portrait.png", "iPhone 11 Pro Max - Portrait.png"] { _ = try sb.png(n, in: png) }
        let r = sb.library.importFolder(sb.source)
        #expect(Set(r.added.compactMap(\.model)) == ["iPhone 11", "iPhone 11 Pro", "iPhone 11 Pro Max"])
    }

    // MARK: 同梱ベゼル

    @Test func installBundledCopiesPNGsAndDetectsWindow() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let bundle = sb.root.appendingPathComponent("Bezels")
        _ = try sb.png("Bezel-Test-1.png", in: bundle)
        try sb.library.installBundledIfNeeded(from: bundle)
        let list = try sb.library.list()
        #expect(list.count == 1 && list[0].name == "Test 1")
    }

    @Test func installBundledPrefersShippedJSON() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let bundle = sb.root.appendingPathComponent("Bezels")
        _ = try sb.png("b.png", in: bundle)
        let shipped = TestSupport.bezel(name: "Shipped", file: "ignored.png", width: 100, height: 200,
                                        aperture: TestSupport.aperture(1, 2, 3, 4))
        try shipped.write(to: bundle.appendingPathComponent("b.json"))
        try sb.library.installBundledIfNeeded(from: bundle)
        let b = try #require(sb.library.list().first)
        #expect(b.name == "Shipped" && b.bezelFile == "b.png" && b.aperture.x == 1)
    }

    @Test func installBundledRunsOnlyOnce() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let bundle = sb.root.appendingPathComponent("Bezels")
        _ = try sb.png("a.png", in: bundle)
        try sb.library.installBundledIfNeeded(from: bundle)
        try sb.library.delete(try #require(sb.library.list().first))
        try sb.library.installBundledIfNeeded(from: bundle)
        #expect(try sb.library.list().isEmpty) // 削除したものは復活しない
    }

    @Test func installBundledWithoutDirectoryStillMarksAsDone() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        try sb.library.installBundledIfNeeded(from: nil)
        let bundle = sb.root.appendingPathComponent("Bezels")
        _ = try sb.png("a.png", in: bundle)
        try sb.library.installBundledIfNeeded(from: bundle)
        #expect(try sb.library.list().isEmpty)
    }

    @Test func installBundledDropsUndetectablePNG() throws {
        let sb = try Sandbox(); defer { sb.cleanup() }
        let bundle = sb.root.appendingPathComponent("Bezels")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try ImageFile.writePNG(TestSupport.solid(40, 40), to: bundle.appendingPathComponent("solid.png"))
        try sb.library.installBundledIfNeeded(from: bundle)
        #expect(try sb.library.list().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: sb.library.bezelsDirectory.appendingPathComponent("solid.png").path))
    }

    @Test func errorMessagesAreNotEmpty() {
        #expect(BezelLibraryError.notPNG.errorDescription?.isEmpty == false)
        #expect(BezelLibraryError.notFound.errorDescription?.isEmpty == false)
        #expect(BezelDetectorError.noScreenRegion.errorDescription?.isEmpty == false)
        #expect(BezelDetectorError.cannotReadPixels.errorDescription?.isEmpty == false)
        #expect(ComposeError.contextCreationFailed.errorDescription?.isEmpty == false)
    }
}
