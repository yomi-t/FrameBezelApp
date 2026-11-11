import Testing
@testable import FrameBezelApp

struct AppStoreSizeTests {
    @Test func idsAreUnique() {
        let ids = AppStoreSize.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func allSizesArePositiveAndPortraitOrientedForPhonesAndPads() {
        for s in AppStoreSize.all {
            #expect(s.width > 0 && s.height > 0)
            if s.family == .iPhone || s.family == .iPad { #expect(s.height > s.width, "\(s.title)") }
            if s.family == .mac { #expect(s.width > s.height, "\(s.title)") } // Mac は 16:10 の横長
        }
    }

    @Test func macSizesAreSixteenByTen() {
        for s in AppStoreSize.all where s.family == .mac {
            #expect(s.width * 10 == s.height * 16, "\(s.title)")
        }
    }

    @Test func everyFamilyHasSizes() {
        for f in AppStoreSize.Family.allCases { #expect(AppStoreSize.all.contains { $0.family == f }, "\(f)") }
    }

    @Test func exactlyTheOfficialRequiredSizesAreMarked() {
        let required = AppStoreSize.all.filter(\.isRequired).map { "\($0.width)x\($0.height)" }
        #expect(required.sorted() == ["1179x2556", "2064x2752"])
    }

    @Test func findByID() throws {
        let s = try #require(AppStoreSize.all.first)
        #expect(AppStoreSize.find(id: s.id) == s)
        #expect(AppStoreSize.find(id: "nope") == nil)
        #expect(AppStoreSize.find(id: nil) == nil)
    }

    @Test func titleShowsLabelAndSize() throws {
        let s = try #require(AppStoreSize.all.first { $0.width == 1179 })
        #expect(s.title.contains("1179×2556"))
        #expect(s.id == "iPhone-1179x2556" || s.id.hasSuffix("1179x2556"))
    }

    @Test func phonesAndPadsFollowBezelOrientation() {
        for s in AppStoreSize.all where s.family == .iPhone || s.family == .iPad {
            let p = s.canvas(for: .portrait), l = s.canvas(for: .landscape)
            #expect(p.height > p.width, "\(s.title)")
            #expect(l.width > l.height, "\(s.title)")
            #expect(p.width == l.height && p.height == l.width)
        }
    }

    @Test func macAndWatchAreNeverSwapped() {
        for s in AppStoreSize.all where s.family == .mac || s.family == .watch {
            for o in BezelOrientation.allCases {
                let c = s.canvas(for: o)
                #expect(c.width == s.width && c.height == s.height, "\(s.title)")
            }
        }
    }
}
