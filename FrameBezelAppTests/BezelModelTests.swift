import Testing
import Foundation
import CoreGraphics
@testable import FrameBezelApp

struct BezelModelTests {
    private let legacyJSON = """
    {"name":"iPhone 17","bezelFile":"Bezel-iPhone-17.png","imageWidth":1500,"imageHeight":3000,
     "aperture":{"x":50,"y":60,"width":1400,"height":2880,"cornerRadius":120}}
    """

    @Test func decodesLegacyJSONWithoutOptionalFields() throws {
        let b = try Bezel.decode(from: Data(legacyJSON.utf8))
        #expect(b.name == "iPhone 17" && b.imageWidth == 1500)
        #expect(b.model == nil && b.orientation == nil && b.color == nil)
        #expect(b.aperture.cornerRadius == 120)
    }

    @Test func modelNameFallsBackToName() throws {
        let legacy = try Bezel.decode(from: Data(legacyJSON.utf8))
        #expect(legacy.modelName == "iPhone 17")
        #expect(TestSupport.bezel(name: "X", model: "Y").modelName == "Y")
    }

    @Test func effectiveOrientationPrefersStoredValue() {
        let b = TestSupport.bezel(aperture: TestSupport.aperture(0, 0, 100, 200), orientation: .landscape)
        #expect(b.effectiveOrientation == .landscape)
    }

    @Test func effectiveOrientationIsInferredFromApertureShape() {
        #expect(TestSupport.bezel(aperture: TestSupport.aperture(0, 0, 100, 200)).effectiveOrientation == .portrait)
        #expect(TestSupport.bezel(aperture: TestSupport.aperture(0, 0, 200, 100)).effectiveOrientation == .landscape)
        #expect(TestSupport.bezel(aperture: TestSupport.aperture(0, 0, 100, 100)).effectiveOrientation == .portrait)
    }

    @Test func roundTripsThroughJSONIncludingMetadata() throws {
        let b = TestSupport.bezel(name: "N", model: "iPhone 18 Pro", orientation: .landscape, color: "Deep Blue")
        #expect(try Bezel.decode(from: b.encoded()) == b)
    }

    @Test func writeAndLoadFromDisk() throws {
        let dir = try TestSupport.makeTempDirectory(); defer { TestSupport.remove(dir) }
        let url = dir.appendingPathComponent("b.json")
        let b = TestSupport.bezel(model: "M", orientation: .portrait, color: "C")
        try b.write(to: url)
        #expect(try Bezel.load(from: url) == b)
    }

    @Test func encodedJSONIsDeterministic() throws {
        let b = TestSupport.bezel(model: "M")
        #expect(try b.encoded() == b.encoded())
    }

    @Test func invalidJSONThrows() {
        #expect(throws: (any Error).self) { try Bezel.decode(from: Data("{}".utf8)) }
    }

    @Test func idIsBezelFile() {
        #expect(TestSupport.bezel(file: "a.png").id == "a.png")
    }

    @Test func orientationLabels() {
        #expect(BezelOrientation.portrait.label == "縦")
        #expect(BezelOrientation.landscape.label == "横")
        #expect(BezelOrientation.allCases == [.portrait, .landscape])
    }
}

struct BezelNamingExtraTests {
    @Test func orientationFolderNameIsHandledByCallerSoFolderIsModel() {
        let m = BezelNaming.parse(fileName: "iPad Pro - Silver - Landscape.png", folderName: "iPad Pro")
        #expect(m.model == "iPad Pro" && m.color == "Silver" && m.orientation == .landscape)
    }

    @Test func modelOnlyInFileNameWithoutFolder() {
        let m = BezelNaming.parse(fileName: "iPhone 17 - Black.png", folderName: nil)
        #expect(m.model == "iPhone 17" && m.color == "Black" && m.orientation == nil)
    }

    @Test func orientationOnlyFileHasNoColor() {
        let m = BezelNaming.parse(fileName: "iPhone 17 - Portrait.png", folderName: "iPhone 17")
        #expect(m.model == "iPhone 17" && m.color == nil && m.orientation == .portrait)
    }

    @Test func fileNameModelWinsOverFolderWhenItHasSeveralParts() {
        // 仕様変更: ファイル名から機種を読める場合はそちらを優先（フォルダがバンド名などのことがあるため）
        let m = BezelNaming.parse(fileName: "Apple Watch S11 - 42mm - Aluminum Silver + Sport Band Black.png", folderName: "Sport Band")
        #expect(m.model == "Apple Watch S11 42mm")
        #expect(m.color == "Aluminum Silver + Sport Band Black")
    }

    @Test func folderIsUsedWhenFileNameHasNoModel() {
        let m = BezelNaming.parse(fileName: "Black - Portrait.png", folderName: "MyModel")
        #expect(m.model == "MyModel" && m.color == "Black" && m.orientation == .portrait)
    }

    @Test func emptyFolderNameIsTreatedAsNoFolder() {
        let m = BezelNaming.parse(fileName: "iPhone 17 - Black - Portrait.png", folderName: "")
        #expect(m.model == "iPhone 17" && m.color == "Black")
    }

    @Test func plainSingleWordFileWithFolder() {
        let m = BezelNaming.parse(fileName: "frame.png", folderName: "Watch")
        #expect(m.model == "Watch")
        #expect(m.color == "frame")
    }

    @Test func extraWhitespaceAndEmptyPartsAreIgnored() {
        let m = BezelNaming.parse(fileName: "A -  - Black - Portrait.png", folderName: "A")
        #expect(m.color == "Black")
    }
}

struct BezelGroupExtraTests {
    private func bezel(_ model: String?, _ o: BezelOrientation?, _ color: String?, w: Double = 10, h: Double = 20, file: String? = nil) -> Bezel {
        TestSupport.bezel(name: model ?? "legacy", file: file ?? "\(model ?? "legacy")-\(color ?? "-")-\(o.map { "\($0)" } ?? "?").png",
                          aperture: TestSupport.aperture(w, h), model: model, orientation: o, color: color)
    }

    @Test func groupsKeepFirstSeenOrderAndInterleavedModels() {
        let g = BezelCatalog.groups([bezel("B", .portrait, nil), bezel("A", .portrait, nil), bezel("B", .landscape, nil)])
        #expect(g.map(\.model) == ["B", "A"])
        #expect(g[0].bezels.count == 2)
    }

    @Test func emptyInputGivesNoGroups() {
        #expect(BezelCatalog.groups([]).isEmpty)
    }

    @Test func legacyBezelsAreGroupedByName() {
        let g = BezelCatalog.groups([bezel(nil, nil, nil)])
        #expect(g.count == 1 && g[0].model == "legacy")
    }

    @Test func representativePrefersPortrait() {
        let g = BezelCatalog.groups([bezel("A", .landscape, "X"), bezel("A", .portrait, "Y")])[0]
        #expect(g.representative.effectiveOrientation == .portrait)
        let onlyLandscape = BezelCatalog.groups([bezel("A", .landscape, "X")])[0]
        #expect(onlyLandscape.representative.color == "X")
    }

    @Test func orientationsAreListedInStableOrder() {
        let g = BezelCatalog.groups([bezel("A", .landscape, nil), bezel("A", .portrait, nil)])[0]
        #expect(g.orientations == [.portrait, .landscape])
    }

    @Test func colorsAreUniqueInFirstSeenOrderAndSkipNil() {
        let g = BezelCatalog.groups([bezel("A", .portrait, "Black", file: "1"), bezel("A", .portrait, nil, file: "2"),
                                     bezel("A", .portrait, "White", file: "3"), bezel("A", .portrait, "Black", file: "4")])[0]
        #expect(g.colors(for: .portrait) == ["Black", "White"])
        #expect(g.colors(for: .landscape).isEmpty)
    }

    @Test func pickFallsBackWhenOrientationIsMissing() {
        let g = BezelCatalog.groups([bezel("A", .portrait, "Black")])[0]
        #expect(g.pick(orientation: .landscape, color: nil).effectiveOrientation == .portrait)
        #expect(g.pick(orientation: nil, color: "Black").color == "Black")
        #expect(g.pick(orientation: .portrait, color: "Missing").color == "Black")
    }

    @Test func bestMatchFallsBackToPickWhenNothingIsComparable() {
        let g = BezelCatalog.groups([bezel("A", .portrait, "Black")])[0]
        // 幅 0 のスクショは比較できないので pick の結果
        #expect(g.bestMatch(screenshotWidth: 0, screenshotHeight: 0, color: "Black").color == "Black")
    }

    @Test func bestMatchChoosesClosestEvenOutsideTolerance() {
        let g = BezelCatalog.groups([bezel("A", .portrait, nil, w: 10, h: 20), bezel("A", .landscape, nil, w: 20, h: 10)])[0]
        #expect(g.bestMatch(screenshotWidth: 30, screenshotHeight: 10, color: nil).effectiveOrientation == .landscape)
        #expect(g.bestMatch(screenshotWidth: 10, screenshotHeight: 40, color: nil).effectiveOrientation == .portrait)
    }
}

struct BezelNamingAppleFormatsTests {
    private func parse(_ name: String, folder: String? = nil) -> BezelMeta { BezelNaming.parse(fileName: name, folderName: folder) }

    @Test func iPhoneWithOnlyModelAndOrientation() {
        // iPhone 11 の dmg は、機種名と向きだけで色の区別が無い。フォルダは PNG（機種名ではない）
        let m = parse("iPhone 11 Pro Max - Portrait.png", folder: "PNG")
        #expect(m.model == "iPhone 11 Pro Max" && m.color == nil && m.orientation == .portrait)
        // 取り込み元のフォルダ名が dmg 名でも、機種名にならない
        let n = parse("iPhone 11 - Portrait.png", folder: "Bezel-iPhone-11")
        #expect(n.model == "iPhone 11" && n.color == nil)
    }

    @Test func iPhone12HasColorAndOrientation() {
        let m = parse("iPhone 12 Pro - Silver - Landscape.png", folder: "PNG")
        #expect(m.model == "iPhone 12 Pro" && m.color == "Silver" && m.orientation == .landscape)
    }

    @Test func iPhoneWithoutOrientationInTheName() {
        let m = parse("iPhone 13 - Midnight.png", folder: "iPhone 13")
        #expect(m.model == "iPhone 13" && m.color == "Midnight" && m.orientation == nil)
    }

    @Test func iPadModelsWithParentheses() {
        let a = parse("iPad (A16) - Blue - Landscape.png", folder: "PNG")
        #expect(a.model == "iPad (A16)" && a.color == "Blue" && a.orientation == .landscape)
        let b = parse("iPad Air 11\" (M4) - Space Gray - Portrait.png", folder: "PNG")
        #expect(b.model == "iPad Air 11\" (M4)" && b.color == "Space Gray")
        let c = parse("iPad Pro (M5) 13\" - Space Black - Portrait.png")
        #expect(c.model == "iPad Pro (M5) 13\"" && c.color == "Space Black")
    }

    @Test func macModelsEndWithInchThenColor() {
        let air = parse("MacBook Air M5 13-inch Sky Blue.png", folder: "PNG")
        #expect(air.model == "MacBook Air M5 13-inch" && air.color == "Sky Blue" && air.orientation == nil)
        let pro = parse("MacBook Pro with PROLED XDR Display 16-inch Space Black.png")
        #expect(pro.model == "MacBook Pro with PROLED XDR Display 16-inch" && pro.color == "Space Black")
        let imac = parse("iMac M4 24-inch Blue.png")
        #expect(imac.model == "iMac M4 24-inch" && imac.color == "Blue")
    }

    @Test func macNeoUsesDashSeparator() {
        let m = parse("MacBook Neo - Blush.png", folder: "PNG")
        #expect(m.model == "MacBook Neo" && m.color == "Blush")
    }

    @Test func studioDisplayBackgroundIsTheColor() {
        let m = parse("Studio Display XDR 2026 On Dark Background.png", folder: "PNG")
        #expect(m.model == "Studio Display XDR 2026" && m.color == "Dark Background")
        #expect(parse("Studio Display 2026 On Light Background.png").color == "Light Background")
    }

    @Test func appleWatchKeepsSizeInModelAndExpandsAbbreviation() {
        let s = parse("Apple Watch S11 - 46mm - Titanium Gold + Milanese Loop.png", folder: "Milanese Loop")
        #expect(s.model == "Apple Watch S11 46mm" && s.color == "Titanium Gold + Milanese Loop" && s.orientation == nil)
        let u = parse("AW Ultra 4 - Natural + Alpine Loop Desert.png", folder: "PNG")
        #expect(u.model == "Apple Watch Ultra 4" && u.color == "Natural + Alpine Loop Desert")
    }

    @Test func duoOrientationSuffixIsSplitFromTheColor() {
        let a = parse("iPhone Duo - Night Sky - Inner Open Landscape.png", folder: "PNG")
        #expect(a.model == "iPhone Duo" && a.color == "Night Sky" && a.variant == "Inner Open" && a.orientation == .landscape)
        let b = parse("iPhone Duo - Star White - Outer Open.png", folder: "PNG")
        #expect(b.model == "iPhone Duo" && b.color == "Star White" && b.variant == "Outer Open" && b.orientation == nil)
    }

    @Test func legacyAndUnparseableNamesStayModelless() {
        let m = parse("Bezel-iPhone-17.png", folder: nil)
        #expect(m.model == nil && m.color == nil)
        let g = parse("Bezel-iPhone-17.png", folder: "PNG") // PNG は機種名として使わない
        #expect(g.model == nil)
    }

    @Test func genericFoldersAreNeverTheModel() {
        for folder in ["PNG", "png", "Photoshop", "Portrait", "Landscape", "Bezel-iPhone-17", ""] {
            #expect(parse("Frame.png", folder: folder).model == nil, "\(folder)")
        }
    }
}

/// ダウンロード済みの Apple 配布ファイル（BezelSources/、Git 管理外）があれば、実際のファイル名を全部解析して崩れが無いか確かめる。
struct BezelSourcesSmokeTests {
    private static let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let root = project.appendingPathComponent("BezelSources", isDirectory: true)
    private static let olderRoot = project.appendingPathComponent("BezelSources-Older", isDirectory: true)

    /// 実ファイルを再帰的に集める
    private static func pngs(in dir: URL) -> [URL] {
        var result: [URL] = []
        let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        while let u = e?.nextObject() as? URL { if u.pathExtension.lowercased() == "png" { result.append(u) } }
        return result
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: BezelSourcesSmokeTests.olderRoot.path)))
    func olderBezelsAreParsedWithoutCollisions() throws {
        let pngs = Self.pngs(in: Self.olderRoot)
        #expect(!pngs.isEmpty)
        var seen: [String: String] = [:]
        for png in pngs {
            var dir = png.deletingLastPathComponent()
            while BezelNaming.genericFolderNames.contains(dir.lastPathComponent.lowercased()) { dir = dir.deletingLastPathComponent() }
            let meta = BezelNaming.parse(fileName: png.lastPathComponent, folderName: dir.lastPathComponent)
            let model = try #require(meta.model, "\(png.lastPathComponent)")
            #expect(DeviceCategory.of(modelName: model) != .other, "\(model)")
            #expect(!model.lowercased().contains("bezel"), "\(model)")
            let key = "\(model)|\(meta.color ?? "-")|\(meta.variant ?? "-")|\(meta.orientation.map { "\($0)" } ?? "?")"
            if let other = seen[key] { Issue.record("重複: \(key) ← \(png.lastPathComponent) / \(other)") }
            seen[key] = png.lastPathComponent
        }
        // ファイル名の機種名と、フォルダ名が一致している（表記が `<機種> <チップ> <サイズ>-inch` にそろっている）
        for png in pngs {
            let meta = BezelNaming.parse(fileName: png.lastPathComponent, folderName: png.deletingLastPathComponent().lastPathComponent)
            if png.pathComponents.contains("Mac") {
                #expect(meta.model == png.deletingLastPathComponent().lastPathComponent, "\(png.lastPathComponent)")
            }
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: BezelSourcesSmokeTests.root.path)))
    func everyRealFileNameGetsAModelAndUniqueVariants() throws {
        let pngs = Self.pngs(in: Self.root)
        #expect(pngs.count > 100)

        var seen: [String: String] = [:]
        for png in pngs {
            var dir = png.deletingLastPathComponent()
            while BezelNaming.genericFolderNames.contains(dir.lastPathComponent.lowercased()) { dir = dir.deletingLastPathComponent() }
            // dmg 名のフォルダ（Bezel-…）は機種名として扱われない（parse 側で除外）
            let meta = BezelNaming.parse(fileName: png.lastPathComponent, folderName: dir.lastPathComponent)
            let model = try #require(meta.model, "\(png.lastPathComponent)")
            #expect(!model.lowercased().contains("bezel") && model != "PNG", "\(png.lastPathComponent) → \(model)")
            #expect(DeviceCategory.of(modelName: model) != .other, "\(model) の種類を判定できない")
            // 同じ機種・色・向きの組が別ファイルに重ならない（重なると取り込み時に重複扱いで落ちる）
            let key = "\(model)|\(meta.color ?? "-")|\(meta.variant ?? "-")|\(meta.orientation.map { "\($0)" } ?? "?")"
            if let other = seen[key] { Issue.record("重複: \(key) ← \(png.lastPathComponent) / \(other)") }
            seen[key] = png.lastPathComponent
        }
    }
}

struct OfficialNameTests {
    @Test func bezelPrefixIsRemovedInAnyStyle() {
        #expect(BezelNaming.officialName("Bezel-iPhone-17") == "iPhone-17")
        #expect(BezelNaming.officialName("Bezel iPhone 17") == "iPhone 17")
        #expect(BezelNaming.officialName("bezel_iPad Pro") == "iPad Pro")
        #expect(BezelNaming.officialName("BEZEL-Bezel-iMac M4") == "iMac M4")
        #expect(BezelNaming.officialName("  iPhone 17 ") == "iPhone 17")
    }

    @Test func namesThatMerelyStartWithBezelLettersAreKept() {
        #expect(BezelNaming.officialName("Bezelless Phone") == "Bezelless Phone")
        #expect(BezelNaming.officialName("iPhone 17") == "iPhone 17")
    }

    @Test func parsedModelNeverStartsWithBezel() {
        let m = BezelNaming.parse(fileName: "Bezel iPhone 17 - Black - Portrait.png", folderName: nil)
        #expect(m.model == "iPhone 17" && m.color == "Black")
    }

    @Test func modelNameOfLegacyBezelIsCleaned() {
        #expect(TestSupport.bezel(name: "Bezel iPhone 17").modelName == "iPhone 17")
        #expect(TestSupport.bezel(name: "X", model: "Bezel-iPad Air").modelName == "iPad Air")
    }

    @Test func legacyFileNamesGetPlainDisplayNames() {
        #expect(BezelLibrary.defaultName(for: "Bezel-iPhone-17.png") == "iPhone 17")
        #expect(BezelLibrary.defaultName(for: "bezel_iPad_Air.png") == "iPad Air")
    }
}

struct DeviceCategoryTests {
    @Test func classifiesByModelName() {
        let cases: [(String, DeviceCategory)] = [
            ("iPhone 17 Pro Max", .iPhone), ("iPhone Air", .iPhone), ("iPhone Duo", .iPhone), ("iPhone 12 Mini", .iPhone),
            ("iPad (A16)", .iPad), ("iPad Pro (M5) 13\"", .iPad), ("iPad mini (A20 Pro)", .iPad), ("iPad Air 11\" (M4)", .iPad),
            ("MacBook Air M5 13-inch", .mac), ("MacBook Neo", .mac), ("MacBook Pro with PROLED XDR Display 14-inch", .mac),
            ("iMac M4 24-inch", .mac), ("Studio Display XDR 2026", .mac), ("Mac Studio", .mac), ("Mac mini", .mac), ("Mac", .mac),
            ("Apple Watch S11 42mm", .watch), ("Apple Watch Ultra 4", .watch), ("AW Ultra 4", .watch),
            ("Apple TV", .other), ("Vision Pro", .other), ("", .other), ("Macaroni", .other),
        ]
        for (name, expected) in cases { #expect(DeviceCategory.of(modelName: name) == expected, "\(name)") }
    }

    @Test func classificationIgnoresCase() {
        #expect(DeviceCategory.of(modelName: "IPHONE 17") == .iPhone)
        #expect(DeviceCategory.of(modelName: "macbook air") == .mac)
    }

    @Test func labelsAndOrder() {
        #expect(DeviceCategory.allCases.map(\.label) == ["iPhone", "iPad", "Mac", "Watch", "その他"])
    }

    @Test func groupsAndCategoriesFollowTheModelName() {
        func b(_ model: String, _ f: String) -> Bezel { TestSupport.bezel(name: model, file: f, model: model) }
        let groups = BezelCatalog.groups([b("MacBook Neo", "1"), b("iPhone 17", "2"), b("Apple Watch Ultra 4", "3"),
                                          b("iPad (A16)", "4"), b("iPhone 16", "5")])
        #expect(BezelCatalog.categories(groups) == [.iPhone, .iPad, .mac, .watch]) // 定義順
        #expect(groups.filter { $0.category == .iPhone }.map(\.model) == ["iPhone 17", "iPhone 16"])
        #expect(BezelCatalog.categories([]).isEmpty)
    }

    @Test func unknownModelsFormTheOtherCategoryOnlyWhenPresent() {
        let g = BezelCatalog.groups([TestSupport.bezel(name: "Apple TV", file: "t", model: "Apple TV")])
        #expect(BezelCatalog.categories(g) == [.other])
    }
}

struct BezelVariantTests {
    private func parse(_ name: String) -> BezelMeta { BezelNaming.parse(fileName: name, folderName: "PNG") }

    @Test func variantIsSplitFromColorForAllDuoForms() {
        for (file, variant, orientation) in [
            ("iPhone Duo - Night Sky - Inner Open Portrait.png", "Inner Open", BezelOrientation.portrait),
            ("iPhone Duo - Night Sky - Inner Open Landscape.png", "Inner Open", .landscape),
            ("iPhone Duo - Night Sky - Outer Closed Portrait.png", "Outer Closed", .portrait),
            ("iPhone Duo - Night Sky - Outer Closed Landscape.png", "Outer Closed", .landscape),
        ] {
            let m = parse(file)
            #expect(m.model == "iPhone Duo" && m.color == "Night Sky" && m.variant == variant && m.orientation == orientation, "\(file)")
        }
        let open = parse("iPhone Duo - Star White - Outer Open.png")
        #expect(open.color == "Star White" && open.variant == "Outer Open" && open.orientation == nil)
    }

    @Test func variantWithoutColorLeavesColorNil() {
        let m = parse("iPhone Duo - Outer Closed Portrait.png")
        #expect(m.color == nil && m.variant == "Outer Closed" && m.orientation == .portrait)
    }

    @Test func ordinaryColorsNeverBecomeVariants() {
        #expect(parse("iPhone 17 - Black - Portrait.png").variant == nil)
        #expect(parse("MacBook Neo - Blush.png").variant == nil)
        #expect(parse("Apple Watch S11 - 42mm - Aluminum Silver + Sport Band Black.png").variant == nil)
    }

    @Test func variantLabelsAreJapaneseAndUnknownOnesPassThrough() {
        #expect(BezelNaming.variantLabel("Inner Open") == "内側の画面・開く")
        #expect(BezelNaming.variantLabel("Outer Closed") == "外側の画面・閉じる")
        #expect(BezelNaming.variantLabel("Outer Open") == "外側の画面・開く")
        #expect(BezelNaming.variantLabel("Tent") == "Tent")
    }

    @Test func legacyJSONWithoutVariantStillDecodes() throws {
        let json = #"{"name":"X","bezelFile":"x.png","imageWidth":10,"imageHeight":10,"aperture":{"x":0,"y":0,"width":1,"height":1,"cornerRadius":0}}"#
        #expect(try Bezel.decode(from: Data(json.utf8)).variant == nil)
        let b = TestSupport.bezel(model: "iPhone Duo", orientation: .portrait, color: "Night Sky", variant: "Inner Open")
        #expect(try Bezel.decode(from: b.encoded()) == b)
    }
}

struct BezelGroupVariantTests {
    /// Duo 相当: 内側（縦・横）、外側・閉じる（縦・横）、外側・開く（縦のみ）× 色 2
    private func duo() -> BezelModelGroup {
        var list: [Bezel] = []
        for color in ["Night Sky", "Star White"] {
            for (variant, o) in [("Inner Open", BezelOrientation.portrait), ("Inner Open", .landscape),
                                 ("Outer Closed", .portrait), ("Outer Closed", .landscape), ("Outer Open", .landscape)] {
                let w = o == .portrait ? 10.0 : 20.0, h = o == .portrait ? 20.0 : 10.0
                list.append(TestSupport.bezel(name: "Duo", file: "\(color)-\(variant)-\(o).png",
                                              aperture: TestSupport.aperture(w, h), model: "iPhone Duo", orientation: o, color: color, variant: variant))
            }
        }
        return BezelCatalog.groups(list)[0]
    }

    @Test func variantsAreOrderedCanonically() {
        #expect(duo().variants == ["Inner Open", "Outer Closed", "Outer Open"])
        let shuffled = BezelCatalog.groups(duo().bezels.reversed())[0]
        #expect(shuffled.variants == ["Inner Open", "Outer Closed", "Outer Open"])
    }

    @Test func orientationsDependOnTheVariant() {
        let g = duo()
        #expect(g.orientations(variant: "Inner Open") == [.portrait, .landscape])
        #expect(g.orientations(variant: "Outer Closed") == [.portrait, .landscape])
        #expect(g.orientations(variant: "Outer Open") == [.landscape]) // 開いた外側は 1 種類だけ
        #expect(g.orientations(variant: nil) == [.portrait, .landscape])
    }

    @Test func colorsAreListedPerVariantWithoutVariantNames() {
        let g = duo()
        #expect(g.colors(for: .portrait, variant: "Inner Open") == ["Night Sky", "Star White"])
        #expect(g.colors(for: .portrait, variant: "Outer Open").isEmpty)
        #expect(g.colors(for: .landscape, variant: "Outer Open") == ["Night Sky", "Star White"])
    }

    @Test func pickKeepsOrientationAndColorWhenSwitchingVariant() {
        let g = duo()
        let b = g.pick(orientation: .landscape, color: "Star White", variant: "Outer Closed")
        #expect(b.variant == "Outer Closed" && b.effectiveOrientation == .landscape && b.color == "Star White")
    }

    @Test func pickFallsBackWhenTheVariantLacksThatOrientation() {
        let b = duo().pick(orientation: .portrait, color: "Night Sky", variant: "Outer Open")
        #expect(b.variant == "Outer Open" && b.effectiveOrientation == .landscape && b.color == "Night Sky")
    }

    @Test func defaultVariantIsTheFirstOne() {
        let g = duo()
        #expect(g.pick(orientation: .portrait, color: nil).variant == "Inner Open")
        #expect(g.pick(orientation: nil, color: nil, variant: "Unknown").variant == "Inner Open")
        #expect(g.representative.variant == "Inner Open" && g.representative.effectiveOrientation == .portrait)
    }

    @Test func bestMatchStaysInsideTheVariant() {
        let g = duo()
        let wide = g.bestMatch(screenshotWidth: 200, screenshotHeight: 100, color: nil, variant: "Outer Closed")
        #expect(wide.variant == "Outer Closed" && wide.effectiveOrientation == .landscape)
        let tall = g.bestMatch(screenshotWidth: 100, screenshotHeight: 200, color: nil, variant: "Outer Open")
        #expect(tall.variant == "Outer Open") // 縦は無いので、あるものから選ぶ
    }

    @Test func groupsWithoutVariantsBehaveAsBefore() {
        let g = BezelCatalog.groups([TestSupport.bezel(name: "A", file: "a", aperture: TestSupport.aperture(1, 2), model: "A", orientation: .portrait, color: "Red")])[0]
        #expect(g.variants.isEmpty)
        #expect(g.orientations(variant: "Anything") == [.portrait])
        #expect(g.pick(orientation: .portrait, color: "Red", variant: "Anything").color == "Red")
    }
}

struct BezelTurnedTests {
    /// 100x200 の画像、画面領域 (10, 20) 60x150、角丸 12（縦向き）
    private let portrait = TestSupport.bezel(width: 100, height: 200,
                                             aperture: TestSupport.aperture(10, 20, 60, 150, r: 12),
                                             model: "M", orientation: .portrait, color: "Black", variant: "V")

    @Test func counterClockwiseTurnMakesLandscape() {
        // 点 (x, y) → (y, W − x)。窓の左上 (10,20) は左下 (20, 90) へ、窓全体は 150x60
        let l = portrait.turned(to: .landscape)
        #expect(l.imageWidth == 200 && l.imageHeight == 100)
        #expect(l.aperture == Aperture(x: 20, y: 30, width: 150, height: 60, cornerRadius: 12))
        #expect(l.effectiveOrientation == .landscape && l.orientation == .landscape)
    }

    @Test func clockwiseTurnMakesPortraitFromLandscape() {
        let landscape = TestSupport.bezel(width: 200, height: 100, aperture: TestSupport.aperture(20, 30, 150, 60, r: 12), orientation: .landscape)
        let p = landscape.turned(to: .portrait)
        #expect(p.imageWidth == 100 && p.imageHeight == 200)
        // 点 (x, y) → (H − y, x)
        #expect(p.aperture == Aperture(x: 10, y: 20, width: 60, height: 150, cornerRadius: 12))
    }

    @Test func turningThereAndBackRestoresTheBezel() {
        #expect(portrait.turned(to: .landscape).turned(to: .portrait) == portrait)
        let l = TestSupport.bezel(width: 300, height: 120, aperture: TestSupport.aperture(7, 9, 250, 100), orientation: .landscape)
        #expect(l.turned(to: .portrait).turned(to: .landscape).aperture == l.aperture)
    }

    @Test func turningToTheSameOrientationChangesNothing() {
        #expect(portrait.turned(to: .portrait) == portrait)
    }

    @Test func turnKeepsIdentityAndMetadata() {
        let l = portrait.turned(to: .landscape)
        #expect(l.bezelFile == portrait.bezelFile && l.model == "M" && l.color == "Black" && l.variant == "V" && l.name == portrait.name)
    }

    @Test func turnsWhenOrientationIsInferredFromTheAperture() {
        let legacy = TestSupport.bezel(width: 100, height: 200, aperture: TestSupport.aperture(10, 20, 60, 150)) // orientation nil → 縦
        #expect(legacy.turned(to: .landscape).imageWidth == 200)
        #expect(legacy.turned(to: .portrait) == legacy)
    }

    @Test func quarterTurnsMatchTheDirection() {
        #expect(portrait.quarterTurns(to: .landscape) == 3) // 反時計回り
        #expect(portrait.turned(to: .landscape).quarterTurns(to: .portrait) == 1) // 時計回り
        #expect(portrait.quarterTurns(to: .portrait) == 0)
    }

    @Test func turnedImageAndApertureStayConsistent() throws {
        // 窓を開けた画像を実際に回して、検出した窓が turned(to:) の計算と一致する
        let image = TestSupport.bezelImage(width: 100, height: 200, screen: CGRect(x: 10, y: 20, width: 60, height: 150))
        let registered = TestSupport.bezel(width: 100, height: 200, aperture: try BezelDetector.detect(image: image), orientation: .portrait)
        for target in BezelOrientation.allCases {
            let turned = registered.turned(to: target)
            let rotated = try #require(ImageRotation.rotate(image, Rotation(quarterTurns: registered.quarterTurns(to: target))))
            let detected = try BezelDetector.detect(image: rotated)
            #expect(rotated.width == turned.imageWidth && rotated.height == turned.imageHeight, "\(target)")
            #expect(detected.x == turned.aperture.x && detected.y == turned.aperture.y, "\(target)")
            #expect(detected.width == turned.aperture.width && detected.height == turned.aperture.height, "\(target)")
        }
    }

    @Test func notchSideStaysOnTheLeftWhenTurnedToLandscape() throws {
        // 縦向きの上側にだけ印（上端の中央に切り欠き）がある画像を横にしたとき、印が左側に来る（Apple の横向きと同じ）
        let w = 100, h = 200
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: TestSupport.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 40, y: h - 20, width: 20, height: 20)) // 上端中央
        let rotated = try #require(ImageRotation.rotate(ctx.makeImage()!, Rotation(quarterTurns: 3)))
        #expect(TestSupport.pixel(rotated, 5, 50) == .init(r: 0, g: 0, b: 255, a: 255)) // 左端の中央
        #expect(TestSupport.pixel(rotated, 190, 50) == .init(r: 255, g: 0, b: 0, a: 255))
    }
}

struct BezelSelectionTests {
    private func group(_ items: [(BezelOrientation, String?, Double, Double)], variant: String? = nil) -> BezelModelGroup {
        BezelCatalog.groups(items.enumerated().map { i, t in
            TestSupport.bezel(name: "iPhone M", file: "m\(i).png", width: Int(t.2) + 20, height: Int(t.3) + 20,
                              aperture: TestSupport.aperture(10, 10, t.2, t.3), model: "iPhone M", orientation: t.0, color: t.1, variant: variant)
        })[0]
    }

    @Test func registeredOrientationIsUsedAsIs() {
        let g = group([(.portrait, "Black", 100, 200), (.landscape, "Black", 200, 100)])
        let s = g.selection(orientation: .landscape, color: "Black")
        #expect(!s.isRotated && s.registered.effectiveOrientation == .landscape && s.resolved == s.registered)
        #expect(s.rotation == .none)
    }

    @Test func missingOrientationRotatesTheRegisteredOne() {
        let g = group([(.portrait, "Black", 100, 200)])
        let s = g.selection(orientation: .landscape, color: "Black")
        #expect(s.isRotated && s.registered.effectiveOrientation == .portrait)
        #expect(s.resolved.effectiveOrientation == .landscape && s.resolved.imageWidth == 220)
        #expect(s.rotation.quarterTurns == 3)
        let back = group([(.landscape, nil, 200, 100)]).selection(orientation: .portrait, color: nil)
        #expect(back.isRotated && back.rotation.quarterTurns == 1 && back.resolved.imageHeight == 220)
    }

    @Test func rotatableDevicesAlwaysOfferBothOrientations() {
        #expect(group([(.portrait, "Black", 100, 200)]).selectableOrientations() == [.portrait, .landscape])
        #expect(group([(.landscape, nil, 200, 100)]).selectableOrientations() == [.portrait, .landscape])
    }

    @Test func selectableColorsFallBackToTheSourceOrientation() {
        let g = group([(.portrait, "Black", 100, 200), (.portrait, "White", 100, 200)])
        #expect(g.selectableColors(for: .portrait) == ["Black", "White"])
        #expect(g.selectableColors(for: .landscape) == ["Black", "White"]) // 回転して使うので、元の色を選べる
        let both = group([(.portrait, "Black", 100, 200), (.portrait, "White", 100, 200), (.landscape, "Black", 200, 100)])
        #expect(both.selectableColors(for: .landscape) == ["Black"]) // 横が登録されていれば、その色だけ
    }

    @Test func colorlessModelsHaveNoColors() {
        #expect(group([(.portrait, nil, 100, 200)]).selectableColors(for: .landscape).isEmpty)
    }

    @Test func bestSelectionRotatesWhenThatFitsBetter() {
        let g = group([(.portrait, "Black", 100, 200)])
        let wide = g.bestSelection(screenshotWidth: 200, screenshotHeight: 100, color: "Black")
        #expect(wide.isRotated && wide.orientation == .landscape)
        let tall = g.bestSelection(screenshotWidth: 100, screenshotHeight: 200, color: "Black")
        #expect(!tall.isRotated && tall.orientation == .portrait)
    }

    @Test func bestSelectionNeverRotatesWhenBothOrientationsAreRegistered() {
        // 縦も横も登録されているなら、回転せず登録済みの中から縦横比が近いものを選ぶ（横の窓が多少ずれていても）
        let g = group([(.portrait, nil, 100, 200), (.landscape, nil, 230, 100)])
        let s = g.bestSelection(screenshotWidth: 200, screenshotHeight: 100, color: nil)
        #expect(!s.isRotated && s.registered.effectiveOrientation == .landscape)
        let tall = g.bestSelection(screenshotWidth: 100, screenshotHeight: 200, color: nil)
        #expect(!tall.isRotated && tall.registered.effectiveOrientation == .portrait)
    }

    @Test func bestSelectionWithUnusableScreenshotStillReturnsSomething() {
        let g = group([(.portrait, "Black", 100, 200)])
        let s = g.bestSelection(screenshotWidth: 0, screenshotHeight: 0, color: "Black")
        #expect(s.registered.color == "Black")
    }

    @Test func selectionKeepsColorAndVariant() {
        let g = BezelCatalog.groups([
            TestSupport.bezel(name: "iPhone D", file: "a", aperture: TestSupport.aperture(10, 20), model: "iPhone D", orientation: .portrait, color: "Night", variant: "Inner Open"),
            TestSupport.bezel(name: "iPhone D", file: "b", aperture: TestSupport.aperture(10, 20), model: "iPhone D", orientation: .portrait, color: "White", variant: "Outer Open"),
        ])[0]
        let s = g.selection(orientation: .landscape, color: "White", variant: "Outer Open")
        #expect(s.registered.bezelFile == "b" && s.isRotated)
    }
}

struct FixedOrientationDeviceTests {
    private func fixed(_ model: String, _ items: [(BezelOrientation, String?, Double, Double)]) -> BezelModelGroup {
        BezelCatalog.groups(items.enumerated().map { i, t in
            TestSupport.bezel(name: model, file: "f\(i).png", width: Int(t.2) + 20, height: Int(t.3) + 20,
                              aperture: TestSupport.aperture(10, 10, t.2, t.3), model: model, orientation: t.0, color: t.1)
        })[0]
    }

    @Test func onlyIPhoneAndIPadRotate() {
        #expect(DeviceCategory.iPhone.rotates && DeviceCategory.iPad.rotates)
        #expect(!DeviceCategory.mac.rotates && !DeviceCategory.watch.rotates && !DeviceCategory.other.rotates)
    }

    @Test func macOffersNoOrientationChoice() {
        let mac = fixed("MacBook Neo", [(.landscape, "Blush", 200, 120)])
        #expect(!mac.allowsRotation)
        #expect(mac.selectableOrientations() == [.landscape]) // 選択肢が 1 つなので画面には出さない
    }

    @Test func watchOffersNoOrientationChoice() {
        let watch = fixed("Apple Watch Ultra 4", [(.portrait, "Natural", 100, 120)])
        #expect(watch.selectableOrientations() == [.portrait])
    }

    @Test func fixedDevicesAreNeverRotated() {
        let mac = fixed("MacBook Neo", [(.landscape, "Blush", 200, 120)])
        let s = mac.selection(orientation: .portrait, color: "Blush")
        #expect(!s.isRotated && s.orientation == .landscape && s.resolved == s.registered)
        // スクショが縦長でも回転しない
        let best = mac.bestSelection(screenshotWidth: 100, screenshotHeight: 200, color: "Blush")
        #expect(!best.isRotated && best.orientation == .landscape)
    }

    @Test func fixedDevicesDoNotBorrowColorsFromAnotherOrientation() {
        let mac = fixed("MacBook Neo", [(.landscape, "Blush", 200, 120)])
        #expect(mac.selectableColors(for: .portrait).isEmpty)
    }

    @Test func unknownDevicesWithBothOrientationsRegisteredStillOfferBoth() {
        let g = fixed("Mystery Device", [(.portrait, nil, 100, 200), (.landscape, nil, 200, 100)])
        #expect(g.selectableOrientations() == [.portrait, .landscape])
        let s = g.selection(orientation: .landscape, color: nil)
        #expect(!s.isRotated && s.orientation == .landscape) // 登録されている向きは、回転せずに選べる
    }

    @Test func rotatableDevicesKeepTheirBehavior() {
        let ipad = fixed("iPad (A16)", [(.portrait, "Blue", 100, 200)])
        #expect(ipad.allowsRotation && ipad.selectableOrientations() == [.portrait, .landscape])
        #expect(ipad.selection(orientation: .landscape, color: "Blue").isRotated)
    }
}

struct ModelShortNameTests {
    private func short(_ name: String) -> String { DeviceCategory.of(modelName: name).shortName(of: name) }

    @Test func iPhoneDropsItsPrefix() {
        #expect(short("iPhone 17 Pro Max") == "17 Pro Max")
        #expect(short("iPhone 13 mini") == "13 mini")
        #expect(short("iPhone Air") == "Air")
        #expect(short("iPhone Duo") == "Duo")
    }

    @Test func iPadDropsItsPrefixUnlessItWouldLoseMeaning() {
        #expect(short("iPad Pro (M5) 13\"") == "Pro (M5) 13\"")
        #expect(short("iPad Air 11\" (M4)") == "Air 11\" (M4)")
        #expect(short("iPad mini (A20 Pro)") == "mini (A20 Pro)")
        #expect(short("iPad (A16)") == "iPad (A16)") // 「(A16)」だけでは何か分からない
    }

    @Test func watchDropsItsPrefix() {
        #expect(short("Apple Watch S11 42mm") == "S11 42mm")
        #expect(short("Apple Watch Ultra 4") == "Ultra 4")
    }

    @Test func macAndOthersKeepTheFullName() {
        #expect(short("MacBook Air M5 13-inch") == "MacBook Air M5 13-inch")
        #expect(short("iMac M4 24-inch") == "iMac M4 24-inch")
        #expect(short("Studio Display 2026") == "Studio Display 2026")
        #expect(short("Apple TV") == "Apple TV")
    }

    @Test func nameThatIsOnlyThePrefixIsKept() {
        #expect(DeviceCategory.iPhone.shortName(of: "iPhone") == "iPhone")
        #expect(DeviceCategory.iPhone.shortName(of: "iPhone ") == "iPhone ")
    }

    @Test func matchingIgnoresCaseAndOtherCategoriesAreUntouched() {
        #expect(DeviceCategory.iPhone.shortName(of: "IPHONE 17") == "17")
        #expect(DeviceCategory.iPhone.shortName(of: "iPad Pro") == "iPad Pro") // 種類が違えば省かない
    }

    @Test func everyRealModelHasANonEmptyShortNameThatIsNotLonger() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("BezelSources")
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        var seen = Set<String>()
        let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        while let u = e?.nextObject() as? URL {
            guard u.pathExtension.lowercased() == "png" else { continue }
            guard let model = BezelNaming.parse(fileName: u.lastPathComponent, folderName: "PNG").model else { continue }
            let short = DeviceCategory.of(modelName: model).shortName(of: model)
            #expect(!short.isEmpty && short.count <= model.count, "\(model)")
            seen.insert(model)
        }
        #expect(seen.count > 20)
    }
}

struct MacGenerationNamingTests {
    private func parse(_ name: String) -> BezelMeta { BezelNaming.parse(fileName: name, folderName: "PNG") }

    @Test func generationIsPartOfTheModelNotTheColor() {
        let a = parse("MacBook Air 13\" - 4th Gen - Midnight.png")
        #expect(a.model == "MacBook Air 13\" 4th Gen" && a.color == "Midnight")
        let p = parse("MacBook Pro 14\" - 5th Gen - Silver.png")
        #expect(p.model == "MacBook Pro 14\" 5th Gen" && p.color == "Silver")
    }

    @Test func generationWithYearAndNoColor() {
        let a = parse("MacBook Pro 16\" - 4th Gen (2019).png")
        #expect(a.model == "MacBook Pro 16\" 4th Gen (2019)" && a.color == nil)
        let b = parse("MacBook Pro 15\" - 4th Gen.png")
        #expect(b.model == "MacBook Pro 15\" 4th Gen" && b.color == nil)
    }

    @Test func ordinalVariantsAreRecognized() {
        #expect(parse("iPad Air - 1st Gen - Gray.png").model == "iPad Air 1st Gen")
        #expect(parse("iPad mini - 2nd Gen - Gray.png").model == "iPad mini 2nd Gen")
        #expect(parse("iPad - 3RD GEN - Gray.png").model == "iPad 3RD GEN")
        #expect(parse("Device - 11th Gen - Gray.png").model == "Device 11th Gen")
    }

    @Test func nonGenerationColorsAreNotFolded() {
        #expect(parse("MacBook Pro 14\" - Silver.png").color == "Silver")
        #expect(parse("MacBook Pro 14\" - Gen Z - Silver.png").color == "Gen Z Silver")
    }

    @Test func differentGenerationsAreDifferentModels() {
        #expect(parse("MacBook Pro 15\" - 4th Gen.png").model != parse("MacBook Pro 15\" - 5th Gen.png").model)
    }

    @Test func oldWatchNamingWithMaterialsParses() {
        let s8 = parse("Apple Watch S8 - 41mm - Aluminum - Midnight - Gray.png")
        #expect(s8.model == "Apple Watch S8 41mm" && s8.color == "Aluminum Midnight Gray")
        let ss = parse("Apple Watch S8 - 45mm - SS - Gold + Elderberry.png")
        #expect(ss.model == "Apple Watch S8 45mm" && ss.color == "SS Gold + Elderberry")
        #expect(DeviceCategory.of(modelName: s8.model!) == .watch)
    }
}

struct MacChipNamingTests {
    private func parse(_ name: String, folder: String? = "PNG") -> BezelMeta { BezelNaming.parse(fileName: name, folderName: folder) }

    @Test func chipAndSizeFormReadsAsModelWithColor() {
        let a = parse("MacBook Air M2 13-inch Midnight.png")
        #expect(a.model == "MacBook Air M2 13-inch" && a.color == "Midnight")
        let p = parse("MacBook Pro M1 16-inch Silver.png")
        #expect(p.model == "MacBook Pro M1 16-inch" && p.color == "Silver")
    }

    @Test func nameEndingWithInchHasNoColor() {
        let i = parse("MacBook Pro Intel 15-inch.png")
        #expect(i.model == "MacBook Pro Intel 15-inch" && i.color == nil)
        #expect(parse("MacBook Pro Intel 16-inch.png", folder: nil).model == "MacBook Pro Intel 16-inch")
    }

    @Test func intelAndAppleSiliconAreDifferentModels() {
        #expect(parse("MacBook Pro Intel 16-inch.png").model != parse("MacBook Pro M1 16-inch Silver.png").model)
    }

    @Test func chipNamesAreRankedByRelease() {
        #expect(ModelOrder.score(of: "MacBook Air M2 13-inch") == ModelOrder.score(of: "macbook air m2 13-inch"))
        #expect(ModelOrder.score(of: "MacBook Air M5 13-inch") > ModelOrder.score(of: "MacBook Air M2 13-inch"))
        #expect(ModelOrder.score(of: "MacBook Pro M4 14-inch") > ModelOrder.score(of: "MacBook Pro M1 14-inch"))
        #expect(ModelOrder.score(of: "MacBook Pro M1 14-inch") > ModelOrder.score(of: "MacBook Pro Intel 16-inch"))
        #expect(ModelOrder.score(of: "MacBook Pro Intel 16-inch") > ModelOrder.score(of: "Gadget"))
    }

    @Test func allMacModelsStayInTheMacCategory() {
        for n in ["MacBook Air M2 13-inch", "MacBook Pro M1 14-inch", "MacBook Pro Intel 15-inch"] {
            #expect(DeviceCategory.of(modelName: n) == .mac)
        }
    }
}
