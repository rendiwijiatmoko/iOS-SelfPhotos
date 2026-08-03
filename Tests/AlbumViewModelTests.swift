import XCTest
@testable import ImmichApp

class AlbumListViewModelTests: XCTestCase {
    var mockRepo: MockAlbumRepository!
    var viewModel: AlbumListViewModel!

    override func setUp() {
        super.setUp()
        mockRepo = MockAlbumRepository()
        viewModel = AlbumListViewModel(repo: mockRepo)
    }

    func testInitialState() {
        XCTAssertTrue(viewModel.albums.isEmpty)
        XCTAssertFalse(viewModel.showCreateSheet)
        XCTAssertTrue(viewModel.createAlbumName.isEmpty)
        if case .idle = viewModel.phase {
            // Success
        } else {
            XCTFail("Expected idle phase")
        }
    }

    func testLoadAlbumsSuccess() async {
        let mockAlbums = [
            AlbumResponseDTO(id: "1", albumName: "Summer", description: nil, assetCount: 10, albumThumbnailAssetId: nil, shared: false, createdAt: Date(), assets: nil),
            AlbumResponseDTO(id: "2", albumName: "Shared Album", description: nil, assetCount: 5, albumThumbnailAssetId: nil, shared: true, createdAt: Date(), assets: nil),
        ]
        mockRepo.mockAlbums = mockAlbums

        await viewModel.loadAlbums()

        XCTAssertEqual(viewModel.albums.count, 2)
        XCTAssertEqual(viewModel.myAlbums.count, 1)
        XCTAssertEqual(viewModel.sharedAlbums.count, 1)
    }

    func testLoadAlbumsError() async {
        mockRepo.shouldFail = true

        await viewModel.loadAlbums()

        if case .failed = viewModel.phase {
            XCTAssertTrue(viewModel.albums.isEmpty)
        } else {
            XCTFail("Expected failed phase")
        }
    }

    func testCreateAlbum() async {
        let newAlbum = AlbumResponseDTO(
            id: "new-1",
            albumName: "New Album",
            description: nil,
            assetCount: 0,
            albumThumbnailAssetId: nil,
            shared: false,
            createdAt: Date(),
            assets: nil
        )
        mockRepo.mockCreateResult = newAlbum

        viewModel.createAlbumName = "New Album"
        await viewModel.createAlbum()

        XCTAssertTrue(viewModel.albums.contains { $0.id == "new-1" })
        XCTAssertTrue(viewModel.createAlbumName.isEmpty)
        XCTAssertFalse(viewModel.showCreateSheet)
    }

    func testCreateAlbumEmptyName() async {
        viewModel.createAlbumName = ""
        await viewModel.createAlbum()

        XCTAssertTrue(viewModel.albums.isEmpty)
    }

    func testDeleteAlbum() async {
        let album = AlbumResponseDTO(id: "1", albumName: "To Delete", description: nil, assetCount: 0, albumThumbnailAssetId: nil, shared: false, createdAt: Date(), assets: nil)
        viewModel.albums = [album]

        await viewModel.deleteAlbum("1")

        XCTAssertTrue(viewModel.albums.isEmpty)
    }

    func testAlbumFiltering() async {
        let albums = [
            AlbumResponseDTO(id: "1", albumName: "My Album 1", description: nil, assetCount: 5, albumThumbnailAssetId: nil, shared: false, createdAt: Date(), assets: nil),
            AlbumResponseDTO(id: "2", albumName: "My Album 2", description: nil, assetCount: 3, albumThumbnailAssetId: nil, shared: false, createdAt: Date(), assets: nil),
            AlbumResponseDTO(id: "3", albumName: "Shared Album", description: nil, assetCount: 10, albumThumbnailAssetId: nil, shared: true, createdAt: Date(), assets: nil),
        ]
        viewModel.albums = albums

        XCTAssertEqual(viewModel.myAlbums.count, 2)
        XCTAssertEqual(viewModel.sharedAlbums.count, 1)
        XCTAssertTrue(viewModel.myAlbums.allSatisfy { !$0.shared })
        XCTAssertTrue(viewModel.sharedAlbums.allSatisfy { $0.shared })
    }
}

class MockAlbumRepository: AlbumRepository {
    var mockAlbums: [AlbumResponseDTO] = []
    var mockCreateResult: AlbumResponseDTO?
    var shouldFail = false

    init() {
        let mockSession = SessionManager()
        let mockAPI = MockAPIClient()
        super.init(api: mockAPI)
    }

    override func all() async throws -> [AlbumResponseDTO] {
        if shouldFail {
            throw APIError.unknown
        }
        return mockAlbums
    }

    override func create(name: String, assetIds: [String] = []) async throws -> AlbumResponseDTO {
        if shouldFail {
            throw APIError.unknown
        }
        guard let result = mockCreateResult else {
            throw APIError.unknown
        }
        return result
    }

    override func delete(_ id: String) async throws {
        if shouldFail {
            throw APIError.unknown
        }
        mockAlbums.removeAll { $0.id == id }
    }
}
