import CryptoKit
import Foundation

class BackupRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// SHA1 hex dari isi file — dipakai server untuk deteksi duplikat.
    ///
    /// `Task.detached`, bukan sekadar `async`.
    ///
    /// Fungsi `async` tanpa titik suspensi berjalan di aktor PEMANGGILNYA —
    /// dan pemanggilnya di sini main actor. SHA1 atas berkas puluhan megabyte
    /// di sana berarti antarmuka membeku selama unggahan disiapkan.
    func checksum(for data: Data) async -> String {
        await Task.detached(priority: .utility) {
            Insecure.SHA1.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        }.value
    }

    /// POST /assets/bulk-upload-check menerima {assets: [{id, checksum}]} dan
    /// menjawab {results: [{id, action, reason, ...}]}. Mengembalikan id yang
    /// ditolak karena duplikat.
    /// Untuk jalur UNGGAH: cukup tahu mana yang sudah ada, tanpa peduli id
    /// servernya.
    ///
    /// Sengaja tidak lewat `duplicateMatches`: yang itu membuang entri tanpa
    /// `assetId`, dan `assetId` adalah field opsional. Foto yang dilaporkan
    /// duplikat tanpa menyebut pasangannya akan lolos dari saringan dan
    /// diunggah ulang.
    func checkDuplicates(_ candidates: [(id: String, checksum: String)]) async throws -> Set<String> {
        Set(try await rawResults(candidates)
            .filter { $0.action == "reject" && $0.reason == "duplicate" }
            .map { $0.id })
    }

    /// Sama dengan `checkDuplicates`, tapi membawa serta ID ASET SERVER-nya.
    ///
    /// Jawaban duplikat menyertakan `assetId` — foto mana di server yang isinya
    /// sama. Itu yang membuat pencocokan ini bisa disimpan sebagai `BackupRecord`
    /// dan dipakai ulang: tanpa id itu, yang diketahui cuma "sudah ada di suatu
    /// tempat", dan lencana "ada di keduanya" tidak tahu petak mana yang harus
    /// ditandai.
    func duplicateMatches(
        _ candidates: [(id: String, checksum: String)]
    ) async throws -> [(localID: String, serverAssetID: String)] {
        try await rawResults(candidates).compactMap { entry in
            guard entry.action == "reject", entry.reason == "duplicate",
                  let assetId = entry.assetId
            else { return nil }
            return (entry.id, assetId)
        }
    }

    struct BulkCheckResult: Decodable {
        let id: String
        let action: String
        let reason: String?
        /// Aset server yang isinya sama. OPSIONAL — server tidak selalu
        /// menyebutkannya.
        let assetId: String?
    }

    private func rawResults(
        _ candidates: [(id: String, checksum: String)]
    ) async throws -> [BulkCheckResult] {
        struct AssetCheck: Encodable { let id: String; let checksum: String }
        struct Body: Encodable { let assets: [AssetCheck] }
        struct Response: Decodable { let results: [BulkCheckResult] }

        let body = Body(assets: candidates.map { AssetCheck(id: $0.id, checksum: $0.checksum) })
        let response: Response = try await api.send(
            .json("/assets/bulk-upload-check", method: .post, body: body))
        return response.results
    }

    /// Permintaan unggah beserta badannya yang sudah ditulis KE BERKAS.
    struct PreparedUpload {
        let request: URLRequest
        /// Badan multipart di direktori sementara. Pemanggil yang membuangnya —
        /// sesi latar baru selesai memakainya jauh setelah fungsi ini pulang.
        let bodyFile: URL
    }

    /// Merakit permintaan multipart, menaruh badannya di berkas.
    ///
    /// **Berkas, bukan `Data`, dan itu syarat dari iOS.** `URLSession` latar
    /// hanya menerima `uploadTask(with:fromFile:)`; varian yang menerima `Data`
    /// dijawab dengan pengecualian saat dijalankan. Alasannya masuk akal:
    /// unggahannya diteruskan ke daemon sistem yang hidup di luar proses
    /// aplikasi ini, dan daemon itu perlu sesuatu yang bisa dibacanya sendiri
    /// setelah aplikasinya tidak ada lagi.
    ///
    /// Jalur biasa ikut memakainya — dua perakit multipart untuk satu endpoint
    /// hanya menunggu keduanya menyimpang.
    func makeUploadRequest(
        data fileData: Data,
        filename: String,
        checksum: String,
        deviceAssetId: String,
        createdAt: Date,
        modifiedAt: Date
    ) async throws -> PreparedUpload {
        let (baseURL, authHeaders) = await api.session.requestContext
        guard let baseURL else { throw APIError.invalidURL }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("/assets"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(checksum, forHTTPHeaderField: "x-immich-checksum")

        for (k, v) in authHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let fields = [
            ("deviceAssetId", deviceAssetId),
            ("deviceId", DeviceIdentity.current),
            ("fileCreatedAt", ISO8601DateFormatter().string(from: createdAt)),
            ("fileModifiedAt", ISO8601DateFormatter().string(from: modifiedAt)),
            ("filename", filename),
        ]

        // Perakitan dan penulisannya DI LUAR aktor pemanggil.
        //
        // Target ini menyalakan `SWIFT_APPROACHABLE_CONCURRENCY`, dan itu
        // mengubah aturan mainnya: fungsi `nonisolated async` MEWARISI eksekutor
        // pemanggilnya alih-alih pindah ke kolam umum. Pemanggilnya di sini
        // `BackupService.upload`, yang terikat main actor — jadi merangkai
        // `Data` sebesar seluruh berkas lalu menuliskannya ke disk akan terjadi
        // di utas yang juga menggambar antarmuka. Untuk video 4K itu beberapa
        // detik layar membeku, dan di peluncuran latar itu jatah waktu yang
        // habis sia-sia.
        //
        // `checksum(for:)` di atas sudah lama memakai `Task.detached` dengan
        // alasan yang sama persis.
        let bodyFile = try await Task.detached(priority: .utility) {
            var body = Data()

            func addField(_ name: String, _ value: String) {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append(
                    "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                        .data(using: .utf8)!)
                body.append("\(value)\r\n".data(using: .utf8)!)
            }

            for (name, value) in fields { addField(name, value) }

            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"assetData\"; filename=\"\(filename)\"\r\n"
                    .data(using: .utf8)!)
            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("upload-\(UUID().uuidString).multipart")
            try body.write(to: url, options: .atomic)
            return url
        }.value

        return PreparedUpload(request: request, bodyFile: bodyFile)
    }

    /// Membaca id aset dari jawaban server, atau melempar alasannya.
    ///
    /// `static` supaya sesi latar bisa memakainya juga: saat jawabannya datang,
    /// aplikasinya mungkin baru saja diluncurkan ulang oleh sistem dan tidak
    /// punya repository apa pun yang masih hidup.
    static func assetID(from data: Data, response: URLResponse?) throws -> String {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.server(status: -1, message: nil)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            // Badan jawabannya IKUT dilempar.
            //
            // Immich menjelaskan penolakannya di situ — kredensial kedaluwarsa,
            // format tidak didukung, kuota habis. Membuangnya menyisakan sebuah
            // angka, dan angka itu tidak memberi tahu siapa pun apa yang harus
            // diperbaiki.
            throw APIError.server(
                status: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8))
        }

        struct UploadResponse: Decodable {
            let id: String
            let status: String?
        }
        return try JSONDecoder.immich.decode(UploadResponse.self, from: data).id
    }

    func getStorageInfo() async throws -> ServerStorageDTO {
        try await api.send(.init(path: "/server/storage"))
    }
}
