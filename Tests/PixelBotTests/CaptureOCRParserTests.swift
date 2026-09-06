import XCTest
@testable import PixelBot

final class CaptureOCRParserTests: XCTestCase {
    func testSafeNormalization() {
        it("should normalize only supported OCR characters and whitespace") {
            let value = NumericOCRParser().parse(" OI | lO ", format: .currentAndMaximum)

            XCTAssertEqual(value, ParsedNumericValue(current: 1, maximum: 10))
        }
    }

    func testNineIsNotChangedToSix() {
        it("should not change nine to six when current exceeds maximum") {
            let value = NumericOCRParser().parse("91/61", format: .currentAndMaximum)

            XCTAssertNil(value)
        }
    }

    func testCurrentAboveMaximumIsRejected() {
        it("should reject current values greater than maximum") {
            let value = NumericOCRParser().parse("501/500", format: .currentAndMaximum)

            XCTAssertNil(value)
        }
    }

    func testPunctuationIsNotRemoved() {
        it("should reject punctuation instead of silently removing it") {
            let value = NumericOCRParser().parse("1,000/2,000", format: .currentAndMaximum)

            XCTAssertNil(value)
        }
    }

    func testAmmoRequiresAFullNumber() {
        it("should require the entire ammo result to be numeric") {
            let value = NumericOCRParser().parse("ammo: 42", format: .singleValue)

            XCTAssertNil(value)
        }
    }

    func testUpperBoundIsAccepted() {
        it("should accept the documented numeric upper bound") {
            let value = NumericOCRParser().parse("99999/99999", format: .currentAndMaximum)

            XCTAssertEqual(value, ParsedNumericValue(current: 99_999, maximum: 99_999))
        }
    }

    func testFastHPDelimiterRecovery() {
        it("should recover a slash read as one in the fast HP candidate") {
            let value = NumericOCRParser().parse("5701570", format: .currentAndMaximum)

            XCTAssertEqual(value, ParsedNumericValue(current: 570, maximum: 570))
        }
    }

    func testFastManaDelimiterRecovery() {
        it("should recover a slash read as one in the fast mana candidate") {
            let value = NumericOCRParser().parse("174312400", format: .currentAndMaximum)

            XCTAssertEqual(value, ParsedNumericValue(current: 1_743, maximum: 2_400))
        }
    }

    func testAmbiguousDelimiterRecoveryIsRejected() {
        it("should reject equally plausible slash recovery positions") {
            let value = NumericOCRParser().parse("011199", format: .currentAndMaximum)

            XCTAssertNil(value)
        }
    }

    func testSingleValueDoesNotRecoverDelimiter() {
        it("should keep digit one unchanged for a single numeric value") {
            let value = NumericOCRParser().parse("111", format: .singleValue)

            XCTAssertEqual(value, ParsedNumericValue(current: 111, maximum: nil))
        }
    }
    func testInactiveShieldField() {
        it("should separate mana from an inactive shield") {
            XCTAssertEqual(ManaOCRParser().parse("1915/2790 (0/0)"),
                           ParsedManaReadout(mana: ParsedNumericValue(current: 1915, maximum: 2790),
                                             shield: ParsedNumericValue(current: 0, maximum: 0)))
        }
    }

    func testActiveShieldField() {
        it("should separate mana from active shield capacity") {
            XCTAssertEqual(ManaOCRParser().parse("1913/2790 (1633/1633)"),
                           ParsedManaReadout(mana: ParsedNumericValue(current: 1913, maximum: 2790),
                                             shield: ParsedNumericValue(current: 1633, maximum: 1633)))
        }
    }

    func testUnreadableShieldPreservesMana() {
        it("should preserve mana when the shield is unreadable") {
            XCTAssertEqual(ManaOCRParser().parse("1913/2790 (???"),
                           ParsedManaReadout(mana: ParsedNumericValue(current: 1913, maximum: 2790), shield: nil))
        }
    }

    func testShieldOnlyCannotBecomeMana() {
        it("should reject shield-only text as mana") {
            XCTAssertNil(ManaOCRParser().parse("(1633/1633)").mana)
        }
    }

    func testIndependentSlashRecovery() {
        it("should recover each pair separator independently") {
            XCTAssertEqual(ManaOCRParser().parse("191312790 (163311633)"),
                           ParsedManaReadout(mana: ParsedNumericValue(current: 1913, maximum: 2790),
                                             shield: ParsedNumericValue(current: 1633, maximum: 1633)))
        }
    }

    func testStaleShieldIsUnknown() {
        it("should treat expired shield evidence as unknown") {
            let now = Date()
            let shield = ShieldReadout(current: 0, maximum: 0, confidence: 1,
                                       timestamp: now.addingTimeInterval(-0.251), state: .inactive)
            XCTAssertEqual(shield.state(at: now), .unknown)
        }
    }
    func testManaRejectsAmbiguousSlashRecovery() {
        it("should reject every ambiguous mana split even when digit lengths favor one") {
            XCTAssertNil(ManaOCRParser().parse("11111 (0/0)").mana)
        }
    }

    func testShieldRejectsAmbiguousSlashRecovery() {
        it("should preserve mana but reject an ambiguous shield split") {
            XCTAssertEqual(ManaOCRParser().parse("1913/2790 (11111)"),
                           ParsedManaReadout(mana: ParsedNumericValue(current: 1913, maximum: 2790), shield: nil))
        }
    }
}
