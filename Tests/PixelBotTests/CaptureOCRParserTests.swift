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
}
