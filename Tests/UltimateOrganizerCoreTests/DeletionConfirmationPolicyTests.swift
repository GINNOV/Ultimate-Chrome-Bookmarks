import XCTest
@testable import UltimateOrganizerCore

final class DeletionConfirmationPolicyTests: XCTestCase {
    func testDeletionRequiresConfirmationUnlessSkipSettingIsEnabled() {
        XCTAssertTrue(DeletionConfirmationPolicy.shouldConfirm(skipConfirmation: false))
        XCTAssertFalse(DeletionConfirmationPolicy.shouldConfirm(skipConfirmation: true))
    }
}
