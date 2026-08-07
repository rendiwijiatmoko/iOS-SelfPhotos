import SwiftUI

/// Foto yang belum dicadangkan, dalam bentuk petak.
///
/// Angka "Remainder" saja menimbulkan pertanyaan yang tidak dijawabnya: foto
/// yang MANA? Layar ini menjawabnya, dan itu penting karena sisa yang tidak
/// pernah menyusut biasanya bukan misteri — biasanya video besar, atau foto yang
/// aslinya sudah tidak ada lagi di perangkat.
struct BackupRemainderView: View {
    @State private var library = LocalPhotoLibrary.shared
    @State private var pending: [LocalPhoto] = []

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        Group {
            if pending.isEmpty {
                ContentUnavailableView(
                    "Nothing Left",
                    systemImage: "checkmark.icloud",
                    description: Text("Everything in the selected albums is backed up."))
            } else {
                grid
            }
        }
        .navigationTitle("Remainder")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .onChange(of: library.photos.count) { reload() }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(pending) { photo in
                    LocalThumbnail(id: photo.id)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func reload() {
        let uploaded = SwiftDataManager.shared.uploadedLocalIdentifiers()
        pending = library.photos.filter { !uploaded.contains($0.id) }
    }
}

/// Petak tunggal dari pustaka perangkat.
///
/// Dimuat saat muncul, bukan di muka: daftar sisanya bisa ribuan, dan
/// `LazyVGrid` memang sudah membatasi yang benar-benar hidup di layar.
private struct LocalThumbnail: View {
    let id: String
    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .task {
                guard image == nil else { return }
                image = await LocalPhotoLibrary.shared.thumbnail(
                    for: LocalPhotoLibrary.assetID(for: id),
                    size: CGSize(width: 300, height: 300))
            }
    }
}
