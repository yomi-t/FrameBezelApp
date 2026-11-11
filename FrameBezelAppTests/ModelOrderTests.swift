import Testing
import Foundation
import CoreGraphics
@testable import FrameBezelApp

struct ModelOrderTests {
    private func sorted(_ names: [String]) -> [String] {
        let groups = BezelCatalog.groups(names.enumerated().map { i, n in
            TestSupport.bezel(name: n, file: "f\(i).png", model: n)
        })
        return ModelOrder.sortedNewestFirst(groups).map(\.model)
    }

    @Test func iPhonesRunFromNewestToOldestWithTopModelsFirstInEachGeneration() {
        let shuffled = ["iPhone 11", "iPhone 17", "iPhone 13 mini", "iPhone Air", "iPhone 18 Pro", "iPhone 12 Pro Max", "iPhone 16 Plus",
                        "iPhone 17 Pro Max", "iPhone 18 Pro Max", "iPhone Duo", "iPhone 16", "iPhone 17 Pro", "iPhone 13"]
        #expect(sorted(shuffled) == ["iPhone Duo", "iPhone 18 Pro Max", "iPhone 18 Pro", "iPhone 17 Pro Max", "iPhone 17 Pro",
                                     "iPhone Air", "iPhone 17", "iPhone 16 Plus", "iPhone 16", "iPhone 13", "iPhone 13 mini",
                                     "iPhone 12 Pro Max", "iPhone 11"])
    }

    @Test func tenthGenerationSortsAboveNinthNotAsText() {
        #expect(sorted(["iPhone 9", "iPhone 10", "iPhone 11"]) == ["iPhone 11", "iPhone 10", "iPhone 9"])
    }

    @Test func iPadsAreOrderedByReleaseNotJustByChipName() {
        let names = ["iPad mini (A17 Pro)", "iPad (A16)", "iPad Pro (M5) 13\"", "iPad Air 11\" (M4)", "iPad mini (A20 Pro)",
                     "iPad Pro (M5) 11\"", "iPad Air 13\" (M3)", "iPad Air"]
        let result = sorted(names)
        #expect(result.prefix(2) == ["iPad Air 11\" (M4)", "iPad mini (A20 Pro)"]) // 2026
        #expect(result.last == "iPad Air") // 世代の分からない旧機種は下
        // 2025 の中は上位機種から: Pro > Air > 無印
        let i = { (n: String) in result.firstIndex(of: n)! }
        #expect(i("iPad Pro (M5) 13\"") < i("iPad Air 13\" (M3)") && i("iPad Air 13\" (M3)") < i("iPad (A16)"))
        #expect(i("iPad (A16)") < i("iPad mini (A17 Pro)")) // 2025 > 2024
    }

    @Test func chipNamesContainingProDoNotCountAsProModels() {
        #expect(ModelOrder.score(of: "iPad mini (A20 Pro)") < ModelOrder.score(of: "iPad Air 11\" (M4)"))
        #expect(ModelOrder.score(of: "iPad mini (A17 Pro)") < ModelOrder.score(of: "iPad (A16)"))
        #expect(ModelOrder.tier(of: "ipad mini (a17 pro)") == 1 && ModelOrder.tier(of: "ipad pro (m5) 13\"") == 4)
    }

    @Test func sizesWithinTheSameModelPutTheLargerOneFirst() {
        #expect(sorted(["iPad Pro (M5) 11\"", "iPad Pro (M5) 13\""]) == ["iPad Pro (M5) 13\"", "iPad Pro (M5) 11\""])
        #expect(sorted(["Apple Watch S10 42mm", "Apple Watch S10 46mm"]) == ["Apple Watch S10 46mm", "Apple Watch S10 42mm"])
    }

    @Test func macsFollowChipGenerationAndYear() {
        let names = ["MacBook Pro M4 14-inch", "MacBook Air M5 13-inch", "MacBook Pro M5 14-inch", "iMac M4 24-inch",
                     "MacBook Neo", "Studio Display 2026", "MacBook Pro 14\" 5th Gen", "MacBook Pro 16\" 4th Gen (2019)",
                     "MacBook Air 13\" 4th Gen", "MacBook Pro with PROLED XDR Display 14-inch"]
        let r = sorted(names)
        let i = { (n: String) in r.firstIndex(of: n)! }
        // 2026: PROLED（Pro）> Air M5 > Neo > Studio Display の順に、2025 以前より上
        #expect(Set(r.prefix(4)) == ["MacBook Pro with PROLED XDR Display 14-inch", "MacBook Air M5 13-inch", "MacBook Neo", "Studio Display 2026"])
        #expect(r[0] == "MacBook Pro with PROLED XDR Display 14-inch")
        #expect(i("MacBook Pro M5 14-inch") == 4)                              // 2025
        #expect(i("MacBook Pro M4 14-inch") < i("MacBook Pro 14\" 5th Gen"))   // 2024 > 2021
        #expect(i("iMac M4 24-inch") > i("MacBook Pro M5 14-inch"))
        #expect(i("MacBook Pro 14\" 5th Gen") < i("MacBook Pro 16\" 4th Gen (2019)"))
        #expect(i("MacBook Pro 16\" 4th Gen (2019)") < i("MacBook Air 13\" 4th Gen")) // 2019 > 2018
    }

    @Test func watchesFollowSeriesAndUltraGenerations() {
        let names = ["Apple Watch S8 41mm", "Apple Watch Ultra", "Apple Watch Ultra 2", "Apple Watch S11 46mm", "Apple Watch Ultra 4",
                     "Apple Watch S9 41mm", "Apple Watch Ultra 3", "Apple Watch S10 46mm"]
        #expect(sorted(names) == ["Apple Watch Ultra 4", "Apple Watch Ultra 3", "Apple Watch S11 46mm", "Apple Watch S10 46mm",
                                  "Apple Watch Ultra 2", "Apple Watch S9 41mm", "Apple Watch Ultra", "Apple Watch S8 41mm"])
    }

    @Test func unknownNamesGoToTheBottomInNameOrder() {
        let r = sorted(["Gadget A", "iPhone 17", "Gadget B"])
        #expect(r == ["iPhone 17", "Gadget B", "Gadget A"])
        #expect(ModelOrder.score(of: "Gadget A") == 0)
        #expect(ModelOrder.score(of: "iPhone SE") == 0)
    }

    @Test func scoreIsMonotonicWithinALine() {
        #expect(ModelOrder.score(of: "iPhone 18") > ModelOrder.score(of: "iPhone 17 Pro Max"))
        #expect(ModelOrder.score(of: "iPhone 17 Pro Max") > ModelOrder.score(of: "iPhone 17 Pro"))
        #expect(ModelOrder.score(of: "Apple Watch S11 42mm") > ModelOrder.score(of: "Apple Watch S10 42mm"))
        #expect(ModelOrder.score(of: "iPad Pro (M5) 13\"") > ModelOrder.score(of: "iPad Pro (M4) 13\""))
    }

    @Test func sortingIsStableAndEmptyInputIsFine() {
        #expect(sorted([]).isEmpty)
        #expect(sorted(["iPhone 17"]) == ["iPhone 17"])
        #expect(sorted(["iPhone 16", "iPhone 17"]) == sorted(["iPhone 17", "iPhone 16"]))
    }

    @Test func releaseYearIsTakenFromTheNameWhenItHasOne() {
        #expect(ModelOrder.releaseYear(of: "studio display xdr 2026") == 2026)
        #expect(ModelOrder.releaseYear(of: "macbook pro 16\" 4th gen (2019)") == 2019)
    }
}
