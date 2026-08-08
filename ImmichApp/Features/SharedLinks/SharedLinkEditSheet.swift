import SwiftUI

/// Sunting satu tautan publik.
struct SharedLinkEditSheet: View {
    let link: SharedLinkDTO
    let publicURL: URL?
    /// Mengembalikan pesan kesalahan; nil berarti berhasil dan sheet menutup.
    ///
    /// Pesannya dikembalikan, bukan ditampilkan pemanggil: layar yang memanggil
    /// sedang tertutup sheet ini, dan alert yang dipasang di sana tidak akan
    /// pernah terlihat.
    let onSave: (SharedLinkEditDTO) async -> String?
    let onDelete: () async -> String?

    @Environment(\.dismiss) private var dismiss

    @State private var description: String
    @State private var password: String
    @State private var slug: String
    @State private var showMetadata: Bool
    @State private var allowDownload: Bool
    @State private var allowUpload: Bool
    @State private var hasExpiry: Bool
    @State private var expiresAt: Date
    @State private var isSaving = false
    @State private var showDeleteConfirm = false
    @State private var shareItem: SharedLinkPresentation?
    @State private var didCopy = false
    @State private var errorMessage: String?

    init(
        link: SharedLinkDTO,
        publicURL: URL?,
        onSave: @escaping (SharedLinkEditDTO) async -> String?,
        onDelete: @escaping () async -> String?
    ) {
        self.link = link
        self.publicURL = publicURL
        self.onSave = onSave
        self.onDelete = onDelete

        _description = State(initialValue: link.description ?? "")
        _password = State(initialValue: link.password ?? "")
        _slug = State(initialValue: link.slug ?? "")
        _showMetadata = State(initialValue: link.showMetadata)
        _allowDownload = State(initialValue: link.allowDownload)
        _allowUpload = State(initialValue: link.allowUpload)
        _hasExpiry = State(initialValue: link.expiresAt != nil)
        // Tautan tanpa masa berlaku tetap butuh tanggal awal untuk pickernya;
        // sebulan dari sekarang cukup masuk akal sebagai titik mulai.
        _expiresAt = State(
            initialValue: link.expiresAt
                ?? Calendar.current.date(byAdding: .month, value: 1, to: Date())
                ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                linkSection
                fieldsSection
                permissionsSection
                expirySection
                deleteSection
            }
            .navigationTitle("Edit link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { saveBar }
            .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
            .alert(
                "Something Went Wrong",
                isPresented: errorBinding,
                actions: { Button("OK", role: .cancel) {} },
                message: { Text(errorMessage ?? "") })
            .confirmationDialog(
                "Delete this link?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Link", role: .destructive) { commitDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The photos stay in your library; only the link stops working.")
            }
        }
    }

    // MARK: - Bagian

    private var linkSection: some View {
        Section {
            HStack(spacing: 12) {
                Text(publicURL?.absoluteString ?? "—")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer(minLength: 0)

                Button {
                    copyLink()
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .disabled(publicURL == nil)

                Button {
                    guard let publicURL else { return }
                    shareItem = SharedLinkPresentation(url: publicURL)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .disabled(publicURL == nil)
            }
        } header: {
            Text(link.isAlbum ? "Album shared" : "Individual shared")
        }
    }

    private var fieldsSection: some View {
        Section {
            LabeledContent("Description") {
                TextField("Optional", text: $description)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Password") {
                TextField("None", text: $password)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            LabeledContent("Custom URL") {
                HStack(spacing: 0) {
                    // Awalannya tetap dan tidak bisa disunting — yang boleh
                    // diubah pengguna cuma bagian setelahnya.
                    Text("/s/")
                        .foregroundStyle(.secondary)
                    TextField("random", text: $slug)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        }
    }

    private var permissionsSection: some View {
        Section {
            Toggle("Show metadata", isOn: $showMetadata)
            Toggle("Allow public user to download", isOn: $allowDownload)
            Toggle("Allow public user to upload", isOn: $allowUpload)
        }
    }

    private var expirySection: some View {
        Section("Expire after") {
            Toggle("Never expires", isOn: Binding(
                get: { !hasExpiry },
                set: { hasExpiry = !$0 }))

            if hasExpiry {
                DatePicker(
                    "Expires on",
                    selection: $expiresAt,
                    displayedComponents: [.date, .hourAndMinute])
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete Link", role: .destructive) {
                showDeleteConfirm = true
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Bar simpan

    private var saveBar: some View {
        Button {
            commitSave()
        } label: {
            Label("Update link", systemImage: "checkmark")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isSaving)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
        }
    }

    // MARK: - Aksi

    private func copyLink() {
        guard let publicURL else { return }
        UIPasteboard.general.string = publicURL.absoluteString
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })
    }

    private func commitSave() {
        isSaving = true
        Task {
            errorMessage = await onSave(edit)
            isSaving = false
            if errorMessage == nil { dismiss() }
        }
    }

    private func commitDelete() {
        Task {
            errorMessage = await onDelete()
            if errorMessage == nil { dismiss() }
        }
    }

    /// Perubahan yang benar-benar dikirim.
    ///
    /// Semuanya ikut terkirim, bukan hanya yang berubah: sheet ini punya satu
    /// tombol simpan yang berarti "jadikan seperti yang terlihat sekarang", dan
    /// menghitung selisih per field hanya menambah cara baru untuk meleset.
    private var edit: SharedLinkEditDTO {
        let trimmedSlug = slug.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = description.trimmingCharacters(in: .whitespaces)

        return SharedLinkEditDTO(
            // Current SharedLinkEditDto uses null to clear nullable fields.
            description: .some(trimmedDescription.isEmpty ? nil : trimmedDescription),
            password: .some(password.isEmpty ? nil : password),
            expiresAt: .some(hasExpiry ? expiresAt : nil),
            allowUpload: allowUpload,
            allowDownload: allowDownload,
            showMetadata: showMetadata,
            // Selalu `.some(...)` — bukan `nil` di lapisan luarnya. Lihat catatan
            // di `SharedLinkEditDTO`: hanya bentuk itu yang terkirim, dan isinya
            // yang nil-lah yang jadi `null` dan benar-benar menghapus URL
            // kustomnya.
            slug: .some(trimmedSlug.isEmpty ? nil : trimmedSlug))
    }
}
