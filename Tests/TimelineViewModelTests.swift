import XCTest
@testable import ImmichApp

/// Linimasa kini dibangun dari cache lokal, bukan dari `/timeline/buckets`.
/// Yang diuji karena itu bukan lagi jalur jaringannya, melainkan pengelompokan
/// per bulan dan penyusunan ulang setelah ada aset yang dibuang.
@MainActor
final class TimelineViewModelTests: XCTestCase {
    var viewModel: TimelineViewModel!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = TimelineViewModel()
    }

    override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }

    func testInitialState() {
        XCTAssertTrue(viewModel.sections.isEmpty)
        if case .idle = viewModel.phase {} else {
            XCTFail("Expected idle phase")
        }
    }

    /// Tanpa `SwiftDataManager`, tidak ada apa pun yang bisa dibaca — dan itu
    /// bukan kegagalan, hanya perpustakaan yang belum tersinkron.
    func testLoadWithoutStoreLeavesEmptyTimeline() async {
        await viewModel.loadTimeline()

        XCTAssertTrue(viewModel.sections.isEmpty)
        if case .loaded = viewModel.phase {} else {
            XCTFail("Expected loaded phase")
        }
    }

    func testSetFavoritePatchesInPlace() async {
        viewModel.sections = [
            TimelineSection(
                id: "2024-08",
                title: "August 2024",
                assets: [
                    makeAsset("a"),
                    makeAsset("b"),
                ],
                count: 2,
                startIndex: 0),
        ]

        viewModel.setFavorite("b", to: true)

        XCTAssertFalse(viewModel.sections[0].assets[0].isFavorite)
        XCTAssertTrue(viewModel.sections[0].assets[1].isFavorite)
    }

    /// Section yang kehilangan seluruh isinya ikut hilang, dan offset section
    /// berikutnya dirapatkan — offset itu dipakai sebagai identitas sel di grid,
    /// jadi lubang di tengahnya akan menabrakkan identitas.
    func testRemovingAssetsCompactsSections() async {
        viewModel.sections = [
            TimelineSection(
                id: "2024-08", title: "August 2024",
                assets: [makeAsset("a")], count: 1, startIndex: 0),
            TimelineSection(
                id: "2024-07", title: "July 2024",
                assets: [makeAsset("b"), makeAsset("c")], count: 2, startIndex: 1),
        ]

        viewModel.assetWasRemoved("a")

        XCTAssertEqual(viewModel.sections.count, 1)
        XCTAssertEqual(viewModel.sections[0].id, "2024-07")
        XCTAssertEqual(viewModel.sections[0].startIndex, 0)
        XCTAssertEqual(viewModel.sections[0].count, 2)
    }

    func testFormatBucketTitle() {
        XCTAssertEqual(TimelineViewModel.formatBucketTitle("2024-08"), "August 2024")
        // Kunci yang tidak bisa diurai dikembalikan apa adanya, bukan jadi teks
        // kosong yang menyesatkan.
        XCTAssertEqual(TimelineViewModel.formatBucketTitle("not-a-month"), "not-a-month")
    }

    func testMonthNavigationTargetsFirstAssetInEveryMonth() {
        viewModel.sections = [
            TimelineSection(
                id: "2024-12", title: "December 2024",
                assets: [makeAsset("dec-first"), makeAsset("dec-last")],
                count: 2, startIndex: 0),
            TimelineSection(
                id: "2025-01", title: "January 2025",
                assets: [makeAsset("jan-first")],
                count: 1, startIndex: 2),
        ]

        XCTAssertEqual(viewModel.monthNavigationItems.map(\.id), ["2024-12", "2025-01"])
        XCTAssertEqual(
            viewModel.monthNavigationItems.map(\.targetAssetID),
            ["dec-first", "jan-first"])
    }

    func testYearNavigationCollapsesMonthsAndTargetsFirstAssetOfYear() {
        viewModel.sections = [
            TimelineSection(
                id: "2024-12", title: "December 2024",
                assets: [makeAsset("2024-first")], count: 1, startIndex: 0),
            TimelineSection(
                id: "2025-01", title: "January 2025",
                assets: [makeAsset("2025-first")], count: 1, startIndex: 1),
            TimelineSection(
                id: "2025-06", title: "June 2025",
                assets: [makeAsset("2025-later")], count: 1, startIndex: 2),
        ]

        XCTAssertEqual(viewModel.yearNavigationItems.map(\.id), ["2024", "2025"])
        XCTAssertEqual(
            viewModel.yearNavigationItems.map(\.targetAssetID),
            ["2024-first", "2025-first"])
    }

    private func makeAsset(_ id: String) -> AssetLite {
        AssetLite(
            id: id,
            isVideo: false,
            ratio: 1,
            thumbhash: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            isFavorite: false)
    }
}
