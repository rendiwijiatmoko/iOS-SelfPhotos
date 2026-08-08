import XCTest
@testable import ImmichApp

final class PinCodeContractTests: XCTestCase {
    func testAcceptsFourThroughSixDigits() {
        XCTAssertTrue(PinCodeContract.isValid("1234"))
        XCTAssertTrue(PinCodeContract.isValid("12345"))
        XCTAssertTrue(PinCodeContract.isValid("123456"))
    }

    func testRejectsLengthsOutsideServerContract() {
        XCTAssertFalse(PinCodeContract.isValid("123"))
        XCTAssertFalse(PinCodeContract.isValid("1234567"))
    }

    func testSanitizesInputAndCapsItAtSixDigits() {
        XCTAssertEqual(PinCodeContract.sanitized("12a34"), "1234")
        XCTAssertEqual(PinCodeContract.sanitized("123456789"), "123456")
    }
}
