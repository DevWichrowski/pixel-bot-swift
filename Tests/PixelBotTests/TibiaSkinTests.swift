import XCTest
@testable import PixelBot

final class TibiaSkinTests: XCTestCase {
    func testEveryTibiaSkinAssetLoads() {
        it("should load every Tibia skin asset") {
            let missingAssets = TibiaAsset.allCases.filter {
                TibiaSkin.image(for: $0) == nil
            }

            XCTAssertTrue(missingAssets.isEmpty, "Missing or invalid assets: \(missingAssets)")
        }
    }
}
