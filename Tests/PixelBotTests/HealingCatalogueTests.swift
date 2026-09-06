import XCTest
@testable import PixelBot

final class HealingCatalogueTests: XCTestCase {
    func testVerifiedCatalogue() {
        it("should match every verified spell formula vocation and base cooldown") {
            let expected = [
                "magicPatch|Magic Patch|exura infir|druid,sorcerer,paladin,monk|1|1",
                "lightHealing|Light Healing|exura|druid,sorcerer,paladin,monk|1|1",
                "intenseHealing|Intense Healing|exura gran|druid,sorcerer,paladin,monk|1|1",
                "ultimateHealing|Ultimate Healing|exura vita|druid,sorcerer|1|1",
                "restoration|Restoration|exura max vita|druid,sorcerer|6|1",
                "divineHealing|Divine Healing|exura san|paladin|1|1",
                "salvation|Salvation|exura gran san|paladin|1|1",
                "bruiseBane|Bruise Bane|exura infir ico|knight|2|2",
                "woundCleansing|Wound Cleansing|exura ico|knight|2|2",
                "fairWoundCleansing|Fair Wound Cleansing|exura med ico|knight|2|2",
                "intenseWoundCleansing|Intense Wound Cleansing|exura gran ico|knight|120|2",
                "spiritMend|Spirit Mend|exura gran tio|monk|1|1",
                "recovery|Recovery|utura|knight,paladin|60|1",
                "intenseRecovery|Intense Recovery|utura gran|knight,paladin|60|1",
            ]
            let actual = HealingAction.allCases.map { action in
                "\(action.rawValue)|\(action.name)|\(action.incantation)|\(action.vocations.map(\.rawValue).joined(separator: ","))|\(Int(action.individualCooldown))|\(Int(action.groupCooldown))"
            }
            XCTAssertEqual(actual, expected)
        }
    }

    func testVocationFilters() {
        it("should offer only emergency self healing spells for each vocation family") {
            let expected: [[HealingAction]] = [
                [.bruiseBane, .woundCleansing, .fairWoundCleansing, .intenseWoundCleansing],
                [.magicPatch, .lightHealing, .intenseHealing, .divineHealing, .salvation],
                [.magicPatch, .lightHealing, .intenseHealing, .ultimateHealing, .restoration],
                [.magicPatch, .lightHealing, .intenseHealing, .ultimateHealing, .restoration],
                [.magicPatch, .lightHealing, .intenseHealing, .spiritMend],
            ]
            XCTAssertEqual(HealingVocation.allCases.map { HealingAction.choices(for: $0) }, expected)
        }
    }

    func testPromotedVocationLabels() {
        it("should identify every promoted vocation in the selector") {
            XCTAssertEqual(HealingVocation.allCases.map(\.displayName), [
                "Knight / Elite Knight", "Paladin / Royal Paladin",
                "Sorcerer / Master Sorcerer", "Druid / Elder Druid", "Monk / Exalted Monk",
            ])
        }
    }

    func testAllVocationsDefault() {
        it("should offer all twelve emergency spells without a vocation selection") {
            XCTAssertEqual(HealingAction.choices(for: nil).count, 12)
        }
    }
}
