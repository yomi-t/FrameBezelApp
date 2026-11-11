import Testing
import Foundation
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

    @Test func folderWinsOverModelPartInFileName() {
        let m = BezelNaming.parse(fileName: "Whatever - Red - Portrait.png", folderName: "MyModel")
        #expect(m.model == "MyModel")
        #expect(m.color == "Whatever Red")
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
