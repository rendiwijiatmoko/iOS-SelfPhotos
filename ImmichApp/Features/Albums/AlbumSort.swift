import Foundation
import SwiftUI

/// Urutan daftar album.
///
/// Di luar `AlbumsListView` karena sheet "Add to Album" memakai pilihan yang
/// sama persis. Aturannya bukan sekadar enam nama: setiap urutan berbasis
/// tanggal punya cadangan ke `createdAt`, dan cadangan itulah yang paling mudah
/// terlupa kalau disalin — hasilnya album dari server lama berkumpul di ujung
/// daftar dengan urutan acak, di satu tempat saja.
///
/// Sengaja BUKAN `SortOrder` — nama itu sudah dipakai Foundation.
enum AlbumSort: String, CaseIterable, Identifiable {
    case lastModified, title, assetCount, createdDate, newestPhoto, oldestPhoto

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .lastModified: "Last Modified"
        case .title: "Album Title"
        case .assetCount: "Number of Assets"
        case .createdDate: "Created Date"
        case .newestPhoto: "Most Recent Photo"
        case .oldestPhoto: "Oldest Photo"
        }
    }

    /// Semua urutan berbasis tanggal punya cadangan ke `createdAt`.
    ///
    /// `updatedAt`, `startDate`, dan `endDate` baru dikirim server versi lebih
    /// baru. Tanpa cadangan itu, album dari server lama akan berkumpul di ujung
    /// daftar dengan urutan acak.
    func isOrderedBefore(_ a: AlbumResponseDTO, _ b: AlbumResponseDTO) -> Bool {
        switch self {
        case .lastModified:
            (a.updatedAt ?? a.createdAt) > (b.updatedAt ?? b.createdAt)
        case .title:
            a.albumName.localizedStandardCompare(b.albumName) == .orderedAscending
        case .assetCount:
            a.assetCount > b.assetCount
        case .createdDate:
            a.createdAt > b.createdAt
        case .newestPhoto:
            (a.endDate ?? a.createdAt) > (b.endDate ?? b.createdAt)
        case .oldestPhoto:
            (a.startDate ?? a.createdAt) < (b.startDate ?? b.createdAt)
        }
    }
}

extension Array where Element == AlbumResponseDTO {
    func sorted(by order: AlbumSort) -> [AlbumResponseDTO] {
        sorted(by: order.isOrderedBefore)
    }
}

/// Menu pilih urutan, dengan centang di pilihan yang sedang berlaku.
///
/// Satu view untuk kedua tempat: daftar album dan sheet "Add to Album" harus
/// menawarkan pilihan yang sama, dan menyalin enam barisnya hanya menunggu
/// keduanya menyimpang.
struct AlbumSortMenu: View {
    @Binding var selection: AlbumSort

    var body: some View {
        Menu {
            Picker("Sort", selection: $selection) {
                ForEach(AlbumSort.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }
}
