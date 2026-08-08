import XCTest
@testable import ImmichApp

@MainActor
final class BackupSetupJourneyTests: XCTestCase {
    private var selectedAlbumIDs: Set<String> = []

    func testNoSelectedAlbumStartsAtProfile() {
        let journey = makeJourney()

        journey.refreshForAlbumSelection()

        XCTAssertEqual(journey.step, .profile)
        XCTAssertTrue(journey.isCoachmarkVisible)
    }

    func testSelectedAlbumKeepsJourneyHidden() {
        selectedAlbumIDs = ["recents"]
        let journey = makeJourney()

        journey.refreshForAlbumSelection()

        XCTAssertEqual(journey.step, .idle)
        XCTAssertFalse(journey.isCoachmarkVisible)
    }

    func testSelectingAlbumDismissesActiveJourney() {
        let journey = makeJourney()
        journey.refreshForAlbumSelection()
        selectedAlbumIDs = ["recents"]

        journey.refreshForAlbumSelection()

        XCTAssertEqual(journey.step, .idle)
        XCTAssertFalse(journey.isCoachmarkVisible)
    }

    func testRemovingLastAlbumOffersJourneyAgain() {
        let journey = makeJourney()
        selectedAlbumIDs = ["recents"]
        journey.refreshForAlbumSelection()
        selectedAlbumIDs = []

        journey.refreshForAlbumSelection()

        XCTAssertEqual(journey.step, .profile)
        XCTAssertTrue(journey.isCoachmarkVisible)
    }

    func testSkipSuppressesRepeatedRefreshOnlyForCurrentEmptySelection() {
        let journey = makeJourney()
        journey.refreshForAlbumSelection()
        journey.skip()

        journey.refreshForAlbumSelection()

        XCTAssertEqual(journey.step, .idle)
        XCTAssertFalse(journey.isCoachmarkVisible)

        selectedAlbumIDs = ["recents"]
        journey.refreshForAlbumSelection()
        selectedAlbumIDs = []
        journey.refreshForAlbumSelection()

        XCTAssertEqual(journey.step, .profile)
        XCTAssertTrue(journey.isCoachmarkVisible)
    }

    func testNewAppSessionOffersTipAgainWhenAlbumsRemainEmpty() {
        let firstSession = makeJourney()
        firstSession.refreshForAlbumSelection()
        firstSession.skip()

        let nextSession = makeJourney()
        nextSession.refreshForAlbumSelection()

        XCTAssertEqual(nextSession.step, .profile)
        XCTAssertTrue(nextSession.isCoachmarkVisible)
    }

    func testClosingSettingsReturnsJourneyToProfile() {
        let journey = makeJourney()
        journey.refreshForAlbumSelection()
        journey.advanceToBackupRow()

        journey.returnToProfileIfNeeded()

        XCTAssertEqual(journey.step, .profile)
        XCTAssertTrue(journey.isCoachmarkVisible)
    }

    private func makeJourney() -> BackupSetupJourney {
        BackupSetupJourney(hasSelectedAlbums: { !self.selectedAlbumIDs.isEmpty })
    }
}
