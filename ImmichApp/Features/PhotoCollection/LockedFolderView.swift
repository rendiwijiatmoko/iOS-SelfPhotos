import SwiftUI

/// Status PIN sesi, dari `GET /auth/status`.
struct AuthStatusDTO: Decodable {
    /// Apakah pengguna SUDAH punya PIN. Kalau belum, ia harus membuatnya dulu.
    let pinCode: Bool
    /// Apakah sesi ini sudah dibuka dan boleh melihat isi Locked Folder.
    let isElevated: Bool
}

/// Aksi PIN untuk Locked Folder.
final class PinRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func status() async throws -> AuthStatusDTO {
        try await api.send(.init(path: "/auth/status"))
    }

    /// Membuka sesi supaya isi Locked Folder bisa diambil.
    ///
    /// Elevasinya melekat pada SESI, bukan pada permintaan — karena itu tidak
    /// ada yang perlu disimpan di sisi klien setelah ini berhasil.
    func unlock(pin: String) async throws {
        try await api.sendVoid(
            .json("/auth/session/unlock", method: .post, body: ["pinCode": pin]))
    }

    func lock() async throws {
        try await api.sendVoid(.init(path: "/auth/session/lock", method: .post))
    }

    /// Membuat PIN pertama kali.
    func createPin(_ pin: String) async throws {
        try await api.sendVoid(
            .json("/auth/pin-code", method: .post, body: ["pinCode": pin]))
    }
}

/// Locked Folder: isinya baru dimuat setelah PIN dimasukkan.
///
/// Gerbangnya di sini, bukan di dalam `PhotoCollectionScreen`: elevasi sesi
/// adalah urusan autentikasi, dan menaruhnya di komponen grid berarti setiap
/// koleksi lain ikut membawa cabang yang tidak pernah dipakainya.
struct LockedFolderView: View {
    @Environment(SessionManager.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var repo: PinRepository?
    @State private var status: AuthStatusDTO?
    @State private var isChecking = true
    @State private var showPinSheet = false
    /// Penjaga supaya penguncian ulang hanya terjadi saat BENAR-BENAR masuk.
    ///
    /// `task` ikut berjalan lagi setiap kembali dari layar detail foto —
    /// mendorong satu foto lalu menutupnya tidak boleh dihitung sebagai membuka
    /// folder ini dari awal, kalau tidak PIN-nya diminta terus-menerus.
    @State private var hasEntered = false
    /// PIN sudah benar dan statusnya sedang diperiksa ulang ke server.
    ///
    /// Selama ini menyala, menutupnya sheet TIDAK berarti membatalkan.
    @State private var isVerifying = false

    var body: some View {
        content
            .navigationTitle("Locked Folder")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPinSheet, onDismiss: leaveIfStillLocked) {
                pinSheet
            }
            .task {
                guard !hasEntered else { return }
                hasEntered = true
                await enter()
            }
    }

    @ViewBuilder
    private var content: some View {
        if isChecking {
            ProgressView()
        } else if isUnlocked {
            AssetCollectionView(
                title: "Locked Folder",
                request: SearchRequestDTO(size: 200, visibility: "locked"),
                layout: .monthly)
        } else {
            lockedPlaceholder
        }
    }

    private var isUnlocked: Bool {
        status?.isElevated == true
    }

    /// Latar di belakang sheet. Tetap ada setelah sheet ditutup manual, jadi
    /// pengguna punya jalan untuk mencoba lagi tanpa keluar-masuk layar.
    private var lockedPlaceholder: some View {
        ContentUnavailableView {
            Label("Locked", systemImage: "lock.fill")
        } description: {
            Text("Enter your PIN to see the photos in this folder.")
        } actions: {
            Button("Enter PIN") { showPinSheet = true }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var pinSheet: some View {
        if let repo {
            PinPromptSheet(
                repo: repo,
                needsSetup: status?.pinCode == false,
                onUnlocked: {
                    // Sheet-nya TIDAK ditutup di sini.
                    //
                    // Menutupnya menjalankan `onDismiss`, dan itu terjadi begitu
                    // animasinya selesai — sementara `/auth/status` masih dalam
                    // perjalanan. Yang terbaca di sana masih status LAMA (belum
                    // elevated), jadi layarnya ikut ditutup persis setelah PIN
                    // yang benar dimasukkan. `checkStatus` yang menutupnya,
                    // setelah jawabannya ada.
                    Task {
                        isVerifying = true
                        await checkStatus(assumingUnlocked: true)
                        isVerifying = false
                    }
                })
            // Tetap ringkas, tetapi cukup untuk petunjuk 4–6 digit dan tombol
            // Continue yang dibutuhkan PIN empat atau lima digit.
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.visible)
        }
    }

    /// Menutup sheet tanpa membuka kunci berarti membatalkan — layarnya ikut
    /// ditutup, bukan meninggalkan halaman kosong yang tidak bisa apa-apa.
    private func leaveIfStillLocked() {
        guard !isUnlocked, !isVerifying else { return }
        dismiss()
    }

    /// Dijalankan sekali per kunjungan.
    ///
    /// Sesi DIKUNCI ULANG lebih dulu, bukan sekadar diperiksa: elevasi bertahan
    /// sampai sesinya kedaluwarsa, jadi tanpa ini sekali memasukkan PIN berarti
    /// folder ini terbuka terus sepanjang sesi — termasuk untuk siapa pun yang
    /// memegang ponselnya setelah itu.
    private func enter() async {
        if repo == nil {
            repo = PinRepository(api: APIClient(session: session))
        }
        try? await repo?.lock()
        await checkStatus()
    }

    /// - Parameter assumingUnlocked: dipanggil tepat setelah PIN diterima.
    ///
    ///   Kalau `/auth/status` gagal di detik itu — jaringan putus sekejap —
    ///   menimpa statusnya dengan nil berarti sheet PIN tidak pernah tertutup
    ///   padahal PIN-nya sudah benar dan input sudah terkirim, sehingga tidak
    ///   bisa dikirim ulang tanpa menghapusnya dulu. Server
    ///   sudah bilang "diterima"; itu cukup untuk melanjutkan.
    private func checkStatus(assumingUnlocked: Bool = false) async {
        if let fresh = try? await repo?.status() {
            status = fresh
        } else if assumingUnlocked {
            status = AuthStatusDTO(pinCode: true, isElevated: true)
        }
        isChecking = false
        showPinSheet = !isUnlocked
    }
}

enum PinCodeContract {
    static let minimumLength = 4
    static let maximumLength = 6

    static func sanitized(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(maximumLength))
    }

    static func isValid(_ value: String) -> Bool {
        (minimumLength...maximumLength).contains(value.count)
            && value.allSatisfy(\.isNumber)
    }
}

/// Sheet masukan PIN sesuai kontrak Immich: empat sampai enam digit.
///
/// Enam digit tetap terkirim otomatis seperti perilaku lama. Untuk PIN empat
/// atau lima digit tersedia tombol Continue karena panjang akhirnya tidak bisa
/// diketahui hanya dari ketikan.
struct PinPromptSheet: View {
    let repo: PinRepository
    /// true kalau pengguna belum pernah membuat PIN sama sekali.
    let needsSetup: Bool
    var onUnlocked: () -> Void

    @State private var pin = ""
    @State private var isWorking = false
    @State private var failureCount = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            Text(needsSetup ? "Create a PIN" : "Enter your PIN")
                .font(.title3.bold())

            Text(needsSetup
                 ? "This PIN protects the photos in your locked folder."
                 : "Your locked folder is protected by a PIN.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Text("Use 4 to 6 digits.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            pinField

            Button {
                Task { await submit() }
            } label: {
                Group {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text("Continue")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)
            .disabled(!PinCodeContract.isValid(pin) || isWorking)

            Spacer(minLength: 0)
        }
        .padding(.top, 32)
        .frame(maxWidth: .infinity)
        // Ketukan salah diberi umpan balik taktil juga, bukan hanya goyangan —
        // jari pengguna sedang menutupi layar saat itu.
        .sensoryFeedback(.error, trigger: failureCount)
        .onAppear { isFocused = true }
    }

    /// Lingkaran-lingkaran di atas satu `TextField` tak terlihat.
    ///
    /// Lebih sederhana daripada papan angka sendiri, dan tetap mendapat papan
    /// ketik angka serta autofill dari sistem.
    private var pinField: some View {
        ZStack {
            TextField("", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .opacity(0.01)
                .onChange(of: pin) { _, newValue in
                    let sanitized = PinCodeContract.sanitized(newValue)
                    if pin != sanitized {
                        pin = sanitized
                    }
                    if sanitized.count == PinCodeContract.maximumLength {
                        Task { await submit() }
                    }
                }

            HStack(spacing: 16) {
                ForEach(0..<PinCodeContract.maximumLength, id: \.self) { index in
                    dot(filled: index < pin.count)
                }
            }
            .allowsHitTesting(false)
            .modifier(ShakeEffect(animatableData: CGFloat(failureCount)))
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    private func dot(filled: Bool) -> some View {
        Circle()
            .strokeBorder(.secondary, lineWidth: 1.5)
            .background(Circle().fill(filled ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear)))
            .frame(width: 16, height: 16)
            .animation(.easeOut(duration: 0.12), value: filled)
    }

    private func submit() async {
        guard !isWorking, PinCodeContract.isValid(pin) else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            if needsSetup {
                try await repo.createPin(pin)
            }
            try await repo.unlock(pin: pin)
            onUnlocked()
        } catch {
            // Digoyang lebih dulu, baru dikosongkan setelah goyangannya selesai
            // — kalau langsung dikosongkan, lingkarannya sudah putih sebelum
            // pengguna sempat melihat penolakannya.
            withAnimation(.linear(duration: shakeDuration)) {
                failureCount += 1
            }
            try? await Task.sleep(for: .seconds(shakeDuration))
            pin = ""
        }
    }
}

private let shakeDuration: Double = 0.4

/// Goyangan mendatar untuk PIN yang ditolak.
///
/// `GeometryEffect`, bukan `offset` yang dianimasikan: nilainya bisa dijalankan
/// sebagai satu animasi utuh dari 0 ke 1 sehingga bolak-baliknya mulus, alih-alih
/// serangkaian animasi pendek yang saling menyusul.
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 8
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: travel * sin(animatableData * .pi * shakes * 2),
            y: 0))
    }
}
