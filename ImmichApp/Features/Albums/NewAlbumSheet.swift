import SwiftUI

/// Membuat album baru: judul, deskripsi, dan — kalau diminta — fotonya sekalian.
///
/// Satu sheet untuk dua tempat yang kebutuhannya beda tipis. Dibuka dari layar
/// Albums, ia layar "New Album" utuh dengan pemilih foto. Dibuka dari sheet
/// "Add to Album", fotonya SUDAH ditentukan sebelum sheet ini muncul — menawarkan
/// pemilih foto lagi di situ hanya menanyakan hal yang barusan dijawab.
struct NewAlbumSheet: View {
    var allowsAssetSelection = true
    /// Membuat albumnya. Mengembalikan pesan kesalahan; nil berarti berhasil dan
    /// sheet-nya menutup.
    var onCreate: (_ name: String, _ description: String, _ assetIds: [String]) async -> String?

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var assetIDs: [String] = []
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showPhotoPicker = false
    @State private var successFeedback = 0
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Album Name", text: $name)
                        .focused($isNameFocused)
                    TextField("Add Description", text: $description, axis: .vertical)
                        .lineLimit(1...4)
                }

                if allowsAssetSelection {
                    Section {
                        Button {
                            showPhotoPicker = true
                        } label: {
                            Label(photoButtonTitle, systemImage: "photo.badge.plus")
                        }
                    } footer: {
                        // Foto boleh nol: album kosong itu sah, dan isinya bisa
                        // ditambahkan kapan saja dari layar albumnya.
                        Text("You can add photos later.")
                    }
                }
            }
            .navigationTitle("New Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showPhotoPicker) {
                AddPhotosToAlbumSheet(existingIDs: Set(assetIDs)) { picked in
                    assetIDs.append(contentsOf: picked)
                }
            }
            .alert(
                "Failed to Create Album",
                isPresented: errorBinding,
                actions: { Button("OK", role: .cancel) {} },
                message: { Text(errorMessage ?? "") })
            .sensoryFeedback(.success, trigger: successFeedback)
            .onAppear { isNameFocused = true }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Create") { create() }
                .disabled(trimmedName.isEmpty || isCreating)
        }
    }

    private var photoButtonTitle: LocalizedStringKey {
        assetIDs.isEmpty
            ? "Select Photos"
            : "^[\(assetIDs.count) Photo](inflect: true) Selected"
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })
    }

    private func create() {
        isCreating = true
        Task {
            errorMessage = await onCreate(
                trimmedName,
                description.trimmingCharacters(in: .whitespaces),
                assetIDs)
            isCreating = false
            guard errorMessage == nil else { return }
            successFeedback += 1
            // Beri SwiftUI satu frame untuk mengirim sensory feedback sebelum
            // seluruh hierarchy sheet dilepas oleh dismiss.
            try? await Task.sleep(for: .milliseconds(50))
            dismiss()
        }
    }
}
