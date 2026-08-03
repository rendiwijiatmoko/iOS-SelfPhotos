import XCTest
@testable import ImmichApp

class TimelineViewModelTests: XCTestCase {
    var mockRepo: MockTimelineRepository!
    var viewModel: TimelineViewModel!

    override func setUp() {
        super.setUp()
        mockRepo = MockTimelineRepository()
        viewModel = TimelineViewModel(repo: mockRepo)
    }

    func testInitialState() {
        XCTAssertTrue(viewModel.sections.isEmpty)
        if case .idle = viewModel.phase {
            // Success
        } else {
            XCTFail("Expected idle phase")
        }
    }

    func testLoadBucketsSuccess() async {
        mockRepo.mockBuckets = [
            TimeBucketDTO(timeBucket: "2026-08", count: 42),
            TimeBucketDTO(timeBucket: "2026-07", count: 30),
        ]

        await viewModel.loadBuckets()

        XCTAssertEqual(viewModel.sections.count, 2)
        XCTAssertEqual(viewModel.sections[0].id, "2026-08")
        XCTAssertEqual(viewModel.sections[1].id, "2026-07")
        if case .loaded = viewModel.phase {
            // Success
        } else {
            XCTFail("Expected loaded phase")
        }
    }

    func testLoadBucketsError() async {
        mockRepo.shouldFail = true

        await viewModel.loadBuckets()

        if case .failed = viewModel.phase {
            XCTAssertTrue(viewModel.sections.isEmpty)
        } else {
            XCTFail("Expected failed phase")
        }
    }

    func testLoadSectionLazy() async {
        mockRepo.mockBuckets = [TimeBucketDTO(timeBucket: "2026-08", count: 5)]
        mockRepo.mockAssets = [
            AssetLite(id: "1", isVideo: false, ratio: 1.0, thumbhash: nil, createdAt: Date()),
            AssetLite(id: "2", isVideo: true, ratio: 0.75, thumbhash: "hash", createdAt: Date()),
        ]

        await viewModel.loadBuckets()
        await viewModel.loadSectionIfNeeded("2026-08")

        XCTAssertEqual(viewModel.sections[0].assets.count, 2)
        XCTAssertEqual(viewModel.sections[0].assets[0].id, "1")
        XCTAssertEqual(viewModel.sections[0].assets[1].id, "2")
    }

    func testLazyLoadOnlyOnce() async {
        mockRepo.mockBuckets = [TimeBucketDTO(timeBucket: "2026-08", count: 1)]
        mockRepo.mockAssets = [AssetLite(id: "1", isVideo: false, ratio: 1.0, thumbhash: nil, createdAt: Date())]

        await viewModel.loadBuckets()
        await viewModel.loadSectionIfNeeded("2026-08")

        let callCountAfterFirst = mockRepo.bucketCallCount

        await viewModel.loadSectionIfNeeded("2026-08")

        // Should not load again
        XCTAssertEqual(mockRepo.bucketCallCount, callCountAfterFirst)
    }

    func testRetry() async {
        mockRepo.shouldFail = true
        await viewModel.loadBuckets()

        if case .failed = viewModel.phase {
            // Expected
        } else {
            XCTFail("Expected failed phase")
        }

        mockRepo.shouldFail = false
        mockRepo.mockBuckets = [TimeBucketDTO(timeBucket: "2026-08", count: 1)]

        await viewModel.retry()

        if case .loaded = viewModel.phase {
            XCTAssertEqual(viewModel.sections.count, 1)
        } else {
            XCTFail("Expected loaded phase after retry")
        }
    }

    func testBucketTitleFormatting() async {
        mockRepo.mockBuckets = [TimeBucketDTO(timeBucket: "2026-08", count: 1)]

        await viewModel.loadBuckets()

        let title = viewModel.sections[0].title
        XCTAssertTrue(title.contains("August") || title.contains("2026"))
    }
}

class MockTimelineRepository: TimelineRepository {
    var mockBuckets: [TimeBucketDTO] = []
    var mockAssets: [AssetLite] = []
    var shouldFail = false
    var bucketCallCount = 0

    init() {
        let mockAPI = MockAPIClient()
        super.init(api: mockAPI)
    }

    override func buckets() async throws -> [TimeBucketDTO] {
        if shouldFail {
            throw APIError.unknown
        }
        return mockBuckets
    }

    override func bucket(_ timeBucket: String) async throws -> [AssetLite] {
        bucketCallCount += 1
        if shouldFail {
            throw APIError.unknown
        }
        return mockAssets
    }
}

class MockAPIClient: APIClient {
    init() {
        let mockSession = SessionManager()
        super.init(session: mockSession)
    }
}
