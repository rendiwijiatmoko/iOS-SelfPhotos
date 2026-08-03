import XCTest
@testable import ImmichApp

class AssetDetailViewModelTests: XCTestCase {
    var mockRepo: MockAssetDetailRepository!
    var viewModel: AssetDetailViewModel!

    override func setUp() {
        super.setUp()
        mockRepo = MockAssetDetailRepository()
        viewModel = AssetDetailViewModel(repo: mockRepo)
    }

    func testInitialState() {
        XCTAssertNil(viewModel.detail)
        XCTAssertFalse(viewModel.showInfoPanel)
        if case .idle = viewModel.phase {
            // Success
        } else {
            XCTFail("Expected idle phase")
        }
    }

    func testLoadAssetSuccess() async {
        let mockAsset = AssetResponseDTO(
            id: "asset-123",
            type: "IMAGE",
            originalFileName: "photo.jpg",
            fileCreatedAt: Date(),
            isFavorite: false,
            isArchived: false,
            isTrashed: false,
            duration: nil,
            thumbhash: "hash",
            localDateTime: Date(),
            exifInfo: nil,
            people: nil
        )
        mockRepo.mockAsset = mockAsset

        await viewModel.load("asset-123")

        XCTAssertEqual(viewModel.detail?.id, "asset-123")
        XCTAssertEqual(viewModel.detail?.originalFileName, "photo.jpg")
        if case .loaded = viewModel.phase {
            // Success
        } else {
            XCTFail("Expected loaded phase")
        }
    }

    func testLoadAssetError() async {
        mockRepo.shouldFail = true

        await viewModel.load("invalid-id")

        if case .failed = viewModel.phase {
            XCTAssertNil(viewModel.detail)
        } else {
            XCTFail("Expected failed phase")
        }
    }

    func testToggleFavorite() async {
        let mockAsset = AssetResponseDTO(
            id: "asset-123",
            type: "IMAGE",
            originalFileName: "photo.jpg",
            fileCreatedAt: Date(),
            isFavorite: false,
            isArchived: false,
            isTrashed: false,
            duration: nil,
            thumbhash: nil,
            localDateTime: Date(),
            exifInfo: nil,
            people: nil
        )
        mockRepo.mockAsset = mockAsset
        await viewModel.load("asset-123")

        let initialState = viewModel.detail?.isFavorite ?? false
        await viewModel.toggleFavorite("asset-123")

        XCTAssertNotEqual(viewModel.detail?.isFavorite, initialState)
        XCTAssertTrue(viewModel.detail?.isFavorite ?? false)
    }

    func testToggleArchive() async {
        let mockAsset = AssetResponseDTO(
            id: "asset-123",
            type: "IMAGE",
            originalFileName: "photo.jpg",
            fileCreatedAt: Date(),
            isFavorite: false,
            isArchived: false,
            isTrashed: false,
            duration: nil,
            thumbhash: nil,
            localDateTime: Date(),
            exifInfo: nil,
            people: nil
        )
        mockRepo.mockAsset = mockAsset
        await viewModel.load("asset-123")

        let initialState = viewModel.detail?.isArchived ?? false
        await viewModel.toggleArchive("asset-123")

        XCTAssertNotEqual(viewModel.detail?.isArchived, initialState)
        XCTAssertTrue(viewModel.detail?.isArchived ?? false)
    }

    func testInfoPanelToggle() {
        XCTAssertFalse(viewModel.showInfoPanel)
        viewModel.showInfoPanel = true
        XCTAssertTrue(viewModel.showInfoPanel)
    }

    func testRetry() async {
        mockRepo.shouldFail = true
        await viewModel.load("asset-123")

        if case .failed = viewModel.phase {
            // Expected
        } else {
            XCTFail("Expected failed phase")
        }

        let mockAsset = AssetResponseDTO(
            id: "asset-123",
            type: "IMAGE",
            originalFileName: "photo.jpg",
            fileCreatedAt: Date(),
            isFavorite: false,
            isArchived: false,
            isTrashed: false,
            duration: nil,
            thumbhash: nil,
            localDateTime: Date(),
            exifInfo: nil,
            people: nil
        )
        mockRepo.shouldFail = false
        mockRepo.mockAsset = mockAsset

        await viewModel.retry("asset-123")

        if case .loaded = viewModel.phase {
            XCTAssertEqual(viewModel.detail?.id, "asset-123")
        } else {
            XCTFail("Expected loaded phase after retry")
        }
    }
}

class MockAssetDetailRepository: AssetDetailRepository {
    var mockAsset: AssetResponseDTO?
    var shouldFail = false

    init() {
        let mockSession = SessionManager()
        let mockAPI = MockAPIClient()
        super.init(api: mockAPI)
    }

    override func fetchAsset(_ id: String) async throws -> AssetResponseDTO {
        if shouldFail {
            throw APIError.unknown
        }
        guard let asset = mockAsset else {
            throw APIError.unknown
        }
        return asset
    }

    override func toggleFavorite(_ id: String, to value: Bool) async throws {
        if shouldFail {
            throw APIError.unknown
        }
        mockAsset?.isFavorite = value
    }

    override func toggleArchive(_ id: String, to value: Bool) async throws {
        if shouldFail {
            throw APIError.unknown
        }
        mockAsset?.isArchived = value
    }

    override func delete(_ id: String) async throws {
        if shouldFail {
            throw APIError.unknown
        }
    }
}
