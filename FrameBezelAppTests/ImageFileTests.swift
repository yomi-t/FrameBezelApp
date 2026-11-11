import Testing
import Foundation
import CoreGraphics
@testable import FrameBezelApp

struct ImageFileTests {
    @Test func writeThenLoadRoundTripsSizeAndColor() throws {
        let dir = try TestSupport.makeTempDirectory(); defer { TestSupport.remove(dir) }
        let url = dir.appendingPathComponent("a.png")
        try ImageFile.writePNG(TestSupport.solid(30, 20, r: 0, g: 1, b: 0), to: url)
        let image = try ImageFile.load(url: url)
        #expect(image.width == 30 && image.height == 20)
        #expect(TestSupport.pixel(image, 5, 5) == TestSupport.RGBA(r: 0, g: 255, b: 0, a: 255))
    }

    @Test func loadFromData() throws {
        let dir = try TestSupport.makeTempDirectory(); defer { TestSupport.remove(dir) }
        let url = dir.appendingPathComponent("a.png")
        try ImageFile.writePNG(TestSupport.solid(8, 6), to: url)
        let image = try ImageFile.load(data: Data(contentsOf: url))
        #expect(image.width == 8 && image.height == 6)
    }

    @Test func invalidDataThrowsCannotDecode() {
        #expect(throws: ImageFileError.self) { try ImageFile.load(data: Data("garbage".utf8)) }
        #expect(throws: ImageFileError.self) { try ImageFile.load(url: URL(fileURLWithPath: "/nonexistent/none.png")) }
    }

    @Test func thumbnailIsBoundedAndKeepsAspect() throws {
        let dir = try TestSupport.makeTempDirectory(); defer { TestSupport.remove(dir) }
        let url = dir.appendingPathComponent("a.png")
        try ImageFile.writePNG(TestSupport.solid(400, 200), to: url)
        let thumb = try #require(ImageFile.thumbnail(url: url, maxPixel: 100))
        #expect(thumb.width == 100 && thumb.height == 50)
    }

    @Test func thumbnailOfMissingFileIsNil() {
        #expect(ImageFile.thumbnail(url: URL(fileURLWithPath: "/nonexistent/none.png"), maxPixel: 50) == nil)
    }

    @Test func writeToMissingDirectoryThrows() {
        let url = URL(fileURLWithPath: "/nonexistent-dir-\(UUID().uuidString)/a.png")
        #expect(throws: ImageFileError.self) { try ImageFile.writePNG(TestSupport.solid(2, 2), to: url) }
    }

    @Test func errorsHaveMessages() {
        #expect(ImageFileError.cannotDecode.errorDescription?.isEmpty == false)
        #expect(ImageFileError.cannotWrite.errorDescription?.isEmpty == false)
    }
}
