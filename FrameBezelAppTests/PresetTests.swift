import Testing
import Foundation
@testable import FrameBezelApp

struct PresetTests {
    private func store() throws -> (PresetStore, URL) {
        let dir = try TestSupport.makeTempDirectory()
        return (PresetStore(directory: dir), dir)
    }

    private func preset(_ name: String, bezel: String? = "a.png", bg: BackgroundStyle = .transparent) -> Preset {
        Preset(name: name, bezelFile: bezel, settings: ComposeSettings(background: bg))
    }

    @Test func loadReturnsEmptyWhenNoFile() throws {
        let (store, dir) = try store(); defer { TestSupport.remove(dir) }
        #expect(store.load().isEmpty)
    }

    @Test func upsertAppendsAndPersists() throws {
        let (store, dir) = try store(); defer { TestSupport.remove(dir) }
        _ = try store.upsert(preset("A"))
        let after = try store.upsert(preset("B"))
        #expect(after.map(\.name) == ["A", "B"])
        #expect(store.load().map(\.name) == ["A", "B"])
    }

    @Test func upsertOverwritesSameNameInPlace() throws {
        let (store, dir) = try store(); defer { TestSupport.remove(dir) }
        _ = try store.upsert(preset("A", bezel: "x.png"))
        _ = try store.upsert(preset("B"))
        let after = try store.upsert(preset("A", bezel: "y.png"))
        #expect(after.map(\.name) == ["A", "B"])
        #expect(after[0].bezelFile == "y.png")
    }

    @Test func deleteRemovesOnlyThatPreset() throws {
        let (store, dir) = try store(); defer { TestSupport.remove(dir) }
        _ = try store.upsert(preset("A")); _ = try store.upsert(preset("B"))
        #expect(try store.delete(name: "A").map(\.name) == ["B"])
        #expect(try store.delete(name: "missing").map(\.name) == ["B"])
    }

    @Test func roundTripsAllBackgroundStyles() throws {
        let (store, dir) = try store(); defer { TestSupport.remove(dir) }
        let styles: [BackgroundStyle] = [
            .transparent,
            .solid(RGBAColor(r: 0.1, g: 0.2, b: 0.3, a: 0.4)),
            .gradient(start: RGBAColor(r: 1, g: 0, b: 0), end: RGBAColor(r: 0, g: 0, b: 1), angleDegrees: 45),
        ]
        for (i, s) in styles.enumerated() { _ = try store.upsert(preset("P\(i)", bg: s)) }
        #expect(store.load().map(\.settings.background) == styles)
    }

    @Test func nilBezelFileSurvivesRoundTrip() throws {
        let (store, dir) = try store(); defer { TestSupport.remove(dir) }
        _ = try store.upsert(preset("A", bezel: nil))
        #expect(store.load().first?.bezelFile == nil)
    }

    @Test func corruptedFileLoadsAsEmpty() throws {
        let (store, dir) = try store(); defer { TestSupport.remove(dir) }
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(store.load().isEmpty)
    }

    @Test func createsMissingDirectoryOnSave() throws {
        let base = try TestSupport.makeTempDirectory(); defer { TestSupport.remove(base) }
        let store = PresetStore(directory: base.appendingPathComponent("nested/dir"))
        _ = try store.upsert(preset("A"))
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(store.fileURL.lastPathComponent == "presets.json")
    }

    @Test func idIsName() {
        #expect(preset("Hello").id == "Hello")
    }
}
