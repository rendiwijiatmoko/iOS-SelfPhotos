import XCTest
@testable import ImmichApp

class DTODecodingTests: XCTestCase {
    let decoder = JSONDecoder.immich

    func testLoginResponseDecoding() throws {
        let json = """
        {
            "accessToken": "abc123token",
            "userId": "user-id-123",
            "userEmail": "user@example.com",
            "name": "John Doe",
            "isAdmin": false,
            "shouldChangePassword": false
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try decoder.decode(LoginResponseDTO.self, from: data)

        XCTAssertEqual(dto.accessToken, "abc123token")
        XCTAssertEqual(dto.userId, "user-id-123")
        XCTAssertEqual(dto.userEmail, "user@example.com")
        XCTAssertEqual(dto.name, "John Doe")
        XCTAssertFalse(dto.isAdmin)
        XCTAssertFalse(dto.shouldChangePassword)
    }

    func testServerPingDecoding() throws {
        let json = #"{"res":"pong"}"#
        let data = json.data(using: .utf8)!
        let dto = try decoder.decode(ServerPingDTO.self, from: data)

        XCTAssertEqual(dto.res, "pong")
    }

    func testServerFeaturesDecoding() throws {
        let json = """
        {
            "smartSearch": true,
            "facialRecognition": true,
            "oauth": false,
            "passwordLogin": true,
            "search": true
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try decoder.decode(ServerFeaturesDTO.self, from: data)

        XCTAssertTrue(dto.smartSearch)
        XCTAssertTrue(dto.facialRecognition)
        XCTAssertFalse(dto.oauth)
        XCTAssertTrue(dto.passwordLogin)
        XCTAssertTrue(dto.search)
    }

    func testUserResponseDecoding() throws {
        let json = """
        {
            "id": "user-123",
            "email": "user@example.com",
            "name": "John Doe",
            "profileImagePath": "/path/to/image.jpg",
            "storageLabel": "primary"
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try decoder.decode(UserResponseDTO.self, from: data)

        XCTAssertEqual(dto.id, "user-123")
        XCTAssertEqual(dto.email, "user@example.com")
        XCTAssertEqual(dto.name, "John Doe")
        XCTAssertEqual(dto.profileImagePath, "/path/to/image.jpg")
        XCTAssertEqual(dto.storageLabel, "primary")
    }

    func testAssetResponseDecoding() throws {
        let json = """
        {
            "id": "asset-123",
            "type": "IMAGE",
            "originalFileName": "photo.jpg",
            "fileCreatedAt": "2026-08-03T10:30:00.000Z",
            "isFavorite": true,
            "isArchived": false,
            "isTrashed": false,
            "duration": null,
            "thumbhash": "abc123hash",
            "localDateTime": "2026-08-03T10:30:00.000Z",
            "exifInfo": null,
            "people": null
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try decoder.decode(AssetResponseDTO.self, from: data)

        XCTAssertEqual(dto.id, "asset-123")
        XCTAssertEqual(dto.type, "IMAGE")
        XCTAssertEqual(dto.originalFileName, "photo.jpg")
        XCTAssertTrue(dto.isFavorite)
        XCTAssertFalse(dto.isArchived)
        XCTAssertFalse(dto.isTrashed)
        XCTAssertFalse(dto.isVideo)
        XCTAssertEqual(dto.thumbhash, "abc123hash")
    }

    func testExifDTODecoding() throws {
        let json = """
        {
            "make": "Canon",
            "model": "EOS 5D Mark IV",
            "exifImageWidth": 4000,
            "exifImageHeight": 3000,
            "fileSizeInByte": 5242880,
            "dateTimeOriginal": "2026-08-03T10:30:00.000Z",
            "latitude": 40.7128,
            "longitude": -74.0060,
            "city": "New York",
            "state": "NY",
            "country": "USA",
            "lensModel": "EF 24-70mm f/2.8L",
            "fNumber": 2.8,
            "focalLength": 50.0,
            "iso": 100,
            "exposureTime": "1/125"
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try decoder.decode(ExifDTO.self, from: data)

        XCTAssertEqual(dto.make, "Canon")
        XCTAssertEqual(dto.model, "EOS 5D Mark IV")
        XCTAssertEqual(dto.exifImageWidth, 4000)
        XCTAssertEqual(dto.exifImageHeight, 3000)
        XCTAssertEqual(dto.city, "New York")
        XCTAssertEqual(dto.country, "USA")
        XCTAssertEqual(dto.latitude, 40.7128)
        XCTAssertEqual(dto.longitude, -74.0060)
    }

    func testTimeBucketDecoding() throws {
        let json = """
        {
            "timeBucket": "2026-08",
            "count": 42
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try decoder.decode(TimeBucketDTO.self, from: data)

        XCTAssertEqual(dto.timeBucket, "2026-08")
        XCTAssertEqual(dto.count, 42)
    }

    func testTimelineBucketColumnarDecoding() throws {
        let json = """
        {
            "id": ["asset-1", "asset-2", "asset-3"],
            "isImage": [true, true, false],
            "isFavorite": [false, true, false],
            "thumbhash": ["hash1", "hash2", "hash3"],
            "fileCreatedAt": ["2026-08-03T10:00:00.000Z", "2026-08-02T15:30:00.000Z", "2026-08-01T12:00:00.000Z"],
            "ratio": [1.5, 1.0, 0.75]
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try decoder.decode(TimelineBucketDTO.self, from: data)

        XCTAssertEqual(dto.id.count, 3)
        XCTAssertEqual(dto.id[0], "asset-1")
        XCTAssertEqual(dto.isImage?[2], false)
        XCTAssertEqual(dto.isFavorite?[1], true)
        XCTAssertEqual(dto.ratio?[0], 1.5)
    }

    func testAlbumResponseDecoding() throws {
        let json = """
        {
            "id": "album-123",
            "albumName": "My Album",
            "description": "A nice album",
            "assetCount": 10,
            "albumThumbnailAssetId": "asset-123",
            "shared": false,
            "createdAt": "2026-08-03T10:30:00.000Z",
            "assets": null
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try decoder.decode(AlbumResponseDTO.self, from: data)

        XCTAssertEqual(dto.id, "album-123")
        XCTAssertEqual(dto.albumName, "My Album")
        XCTAssertEqual(dto.assetCount, 10)
        XCTAssertFalse(dto.shared)
    }

    func testPersonDTODecoding() throws {
        let json = """
        {
            "id": "person-123",
            "name": "John Doe",
            "birthDate": "2000-01-15T00:00:00.000Z",
            "thumbnailPath": "/path/to/thumbnail.jpg",
            "isHidden": false
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try decoder.decode(PersonDTO.self, from: data)

        XCTAssertEqual(dto.id, "person-123")
        XCTAssertEqual(dto.name, "John Doe")
        XCTAssertFalse(dto.isHidden)
    }

    func testMemoryDTODecoding() throws {
        let json = """
        {
            "id": "memory-123",
            "type": "ON_THIS_DAY",
            "memoryAt": "2026-08-03T00:00:00.000Z",
            "assets": []
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try decoder.decode(MemoryDTO.self, from: data)

        XCTAssertEqual(dto.id, "memory-123")
        XCTAssertEqual(dto.type, "ON_THIS_DAY")
        XCTAssertTrue(dto.assets.isEmpty)
    }

    func testSearchResponseDecoding() throws {
        let json = """
        {
            "assets": {
                "items": [
                    {
                        "id": "asset-1",
                        "type": "IMAGE",
                        "originalFileName": "photo1.jpg",
                        "fileCreatedAt": "2026-08-03T10:30:00.000Z",
                        "isFavorite": false,
                        "isArchived": false,
                        "isTrashed": false,
                        "duration": null,
                        "thumbhash": "hash1",
                        "localDateTime": "2026-08-03T10:30:00.000Z",
                        "exifInfo": null,
                        "people": null
                    }
                ],
                "total": 1,
                "nextPage": null
            }
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try decoder.decode(SearchResponseDTO.self, from: data)

        XCTAssertEqual(dto.assets.items.count, 1)
        XCTAssertEqual(dto.assets.total, 1)
        XCTAssertNil(dto.assets.nextPage)
    }

    func testOptionalFieldsHandling() throws {
        let json = """
        {
            "id": "user-123",
            "email": "user@example.com",
            "name": "John",
            "profileImagePath": null,
            "storageLabel": null
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try decoder.decode(UserResponseDTO.self, from: data)

        XCTAssertNil(dto.profileImagePath)
        XCTAssertNil(dto.storageLabel)
    }
}
