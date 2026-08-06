import SwiftUI

/// Deret chip penyaring di bawah kolom cari.
///
/// Chip, bukan satu tombol yang membuka satu sheet berisi semuanya: penyaring
/// yang sedang berlaku harus TERLIHAT tanpa dibuka. Hasil pencarian yang tiba-tiba
/// sedikit karena filter tanggal yang terlupa adalah kebingungan yang mahal, dan
/// satu-satunya penawarnya adalah menampilkannya terus-menerus.
struct SearchFilterBar: View {
    @Binding var filters: SearchFilters
    /// Orang yang bisa dipilih; dimuat pemanggil sekali saja.
    let people: [PersonDTO]
    /// Kota yang bisa dipilih, dari saran server.
    let cities: [String]

    @State private var sheet: FilterSheet?

    private enum FilterSheet: String, Identifiable {
        case people, location, date, mediaType
        var id: String { rawValue }
    }

    var body: some View {
        // Tombol bersihkan DI LUAR area gulir.
        //
        // Di dalamnya, ia terdorong ke ujung kanan deretan chip — dan begitu
        // chip-nya menyala satu per satu, ujung itu makin jauh dari layar.
        // Tombol untuk membatalkan semuanya justru jadi yang paling sulit
        // diraih tepat ketika paling dibutuhkan.
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(
                        label: peopleLabel,
                        isOn: !filters.people.isEmpty,
                        systemImage: "person.crop.circle") { sheet = .people }

                    chip(
                        label: filters.city ?? String(localized: "Location"),
                        isOn: filters.city != nil,
                        systemImage: "mappin.and.ellipse") { sheet = .location }

                    chip(
                        label: filters.dateRange?.label ?? String(localized: "Date"),
                        isOn: filters.dateRange != nil,
                        systemImage: "calendar") { sheet = .date }

                    chip(
                        label: filters.mediaType == .all
                            ? String(localized: "Media Type")
                            : filters.mediaType.label,
                        isOn: filters.mediaType != .all,
                        systemImage: "photo.on.rectangle") { sheet = .mediaType }
                }
                .padding(.horizontal, 16)
            }
            // TANPA `scrollClipDisabled`. Dulu ScrollView memenuhi seluruh bar
            // sehingga klip yang dimatikan tak terlihat akibatnya; sekarang ia
            // punya tetangga di kanan, dan chip yang tergulir lewat tepi akan
            // terlukis menembus ke area tombol bersihkan.

            if filters.isActive {
                Button(role: .destructive) {
                    filters = SearchFilters()
                } label: {
                    Label("Clear", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .padding(.trailing, 16)
            }
        }
        .padding(.vertical, 8)
        // Detent-nya ditentukan MASING-MASING pemilih, bukan dipukul rata di
        // sini: daftar orang butuh ruang, sedangkan jenis media cuma tiga baris
        // dan sheet setinggi separuh layar untuk tiga baris terasa kosong.
        .sheet(item: $sheet) { which in
            sheetContent(which)
        }
    }

    /// Chip yang menyala menampilkan NILAINYA, bukan nama penyaringnya.
    ///
    /// "Last 3 Months" memberi tahu apa yang sedang berlaku; "Date" yang berwarna
    /// hanya memberi tahu bahwa ada sesuatu — dan pengguna tetap harus membukanya
    /// untuk tahu apa.
    private func chip(
        label: String,
        isOn: Bool,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.subheadline)
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(isOn ? .accentColor : .secondary)
    }

    private var peopleLabel: String {
        switch filters.people.count {
        case 0: String(localized: "People")
        case 1: filters.people[0].name.isEmpty
            ? String(localized: "1 Person")
            : filters.people[0].name
        default: String(localized: "\(filters.people.count) People")
        }
    }

    @ViewBuilder
    private func sheetContent(_ which: FilterSheet) -> some View {
        switch which {
        case .people:
            SearchPeoplePicker(selected: $filters.people, people: people)
        case .location:
            SearchCityPicker(selected: $filters.city, cities: cities)
        case .date:
            SearchDatePicker(selected: $filters.dateRange)
        case .mediaType:
            SearchMediaTypePicker(selected: $filters.mediaType)
        }
    }
}

/// Membuat isi sheet BENAR-BENAR bisa disentuh di detent yang bukan terbesar.
///
/// Bawaannya (`.automatic`), gestur pada isi yang bisa digulir diambil alih
/// untuk mengubah ukuran sheet — dan di detent medium itu berarti ketukan pada
/// baris daftar tidak pernah sampai ke barisnya. Pengguna harus menyeret
/// sheet-nya ke penuh dulu baru bisa memilih. `.scrolls` mengembalikan isi
/// sebagai yang diprioritaskan.
private struct FilterSheetPresentation: ViewModifier {
    let detents: Set<PresentationDetent>

    func body(content: Content) -> some View {
        content
            .presentationDetents(detents)
            .presentationContentInteraction(.scrolls)
            .presentationDragIndicator(.visible)
    }
}

extension View {
    fileprivate func filterSheet(_ detents: Set<PresentationDetent>) -> some View {
        modifier(FilterSheetPresentation(detents: detents))
    }
}

// MARK: - Pemilih

private struct SearchPeoplePicker: View {
    @Binding var selected: [PersonDTO]
    let people: [PersonDTO]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(filtered) { person in
                Button {
                    toggle(person)
                } label: {
                    HStack(spacing: 12) {
                        AuthImage(
                            assetId: person.id,
                            path: "/people/\(person.id)/thumbnail")
                        .frame(width: 44, height: 44)
                        .clipShape(.circle)

                        Text(person.name.isEmpty
                            ? String(localized: "Unnamed")
                            : person.name)

                        Spacer()

                        if isSelected(person) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search People")
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { doneToolbar(dismiss) { selected = [] } }
        }
        .filterSheet([.medium, .large])
    }

    private var filtered: [PersonDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return people }
        return people.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private func isSelected(_ person: PersonDTO) -> Bool {
        selected.contains { $0.id == person.id }
    }

    /// Banyak orang sekaligus: mencari foto yang memuat DUA orang tertentu
    /// adalah alasan utama penyaring ini ada.
    private func toggle(_ person: PersonDTO) {
        if let index = selected.firstIndex(where: { $0.id == person.id }) {
            selected.remove(at: index)
        } else {
            selected.append(person)
        }
    }
}

private struct SearchCityPicker: View {
    @Binding var selected: String?
    let cities: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(filtered, id: \.self) { city in
                Button {
                    selected = city
                    dismiss()
                } label: {
                    HStack {
                        Text(city)
                        Spacer()
                        if selected == city {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search Places")
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { doneToolbar(dismiss) { selected = nil } }
        }
        .filterSheet([.medium, .large])
    }

    private var filtered: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return cities }
        return cities.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}

private struct SearchDatePicker: View {
    @Binding var selected: SearchDateRange?

    @Environment(\.dismiss) private var dismiss
    @State private var customFrom = Date()
    @State private var customTo = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(quickRanges, id: \.self) { range in
                        row(range)
                    }
                }

                Section("Custom Range") {
                    DatePicker("From", selection: $customFrom, displayedComponents: .date)
                    DatePicker("To", selection: $customTo, displayedComponents: .date)
                    Button("Use This Range") {
                        selected = .custom(from: customFrom, to: customTo)
                        dismiss()
                    }
                    // Rentang terbalik bukan pilihan yang bisa dijalankan; tombolnya
                    // dimatikan alih-alih diam-diam menukar keduanya.
                    .disabled(customFrom > customTo)
                }
            }
            .navigationTitle("Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { doneToolbar(dismiss) { selected = nil } }
            // Rentang yang sudah dipilih dikembalikan ke pemilihnya. Tanpa ini,
            // membuka lagi sheet-nya menampilkan hari ini/hari ini sementara
            // chip-nya masih menunjukkan rentang yang lama.
            .onAppear {
                if case .custom(let from, let to) = selected {
                    customFrom = from
                    customTo = to
                }
            }
        }
        .filterSheet([.medium, .large])
    }

    private var quickRanges: [SearchDateRange] {
        [.lastMonth, .last3Months, .last9Months]
            + SearchDateRange.recentYears().map(SearchDateRange.year)
    }

    private func row(_ range: SearchDateRange) -> some View {
        Button {
            selected = range
            dismiss()
        } label: {
            HStack {
                Text(range.label)
                Spacer()
                if selected == range {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            // Tanpa ini yang bisa diketuk cuma tulisannya; sisa lebar barisnya
            // — termasuk ruang kosong di tengah — tidak menerima sentuhan.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SearchMediaTypePicker: View {
    @Binding var selected: SearchMediaType

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ForEach(SearchMediaType.allCases) { type in
                    Button {
                        selected = type
                        dismiss()
                    } label: {
                        HStack {
                            Text(type.label)
                            Spacer()
                            if selected == type {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Media Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Tiga baris; setengah layar untuk itu cuma ruang kosong.
        .filterSheet([.height(280)])
    }
}

/// Toolbar seragam untuk sheet penyaring: bersihkan di kiri, selesai di kanan.
@MainActor
@ToolbarContentBuilder
private func doneToolbar(
    _ dismiss: DismissAction,
    clear: @escaping () -> Void
) -> some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
        Button("Clear") {
            clear()
            dismiss()
        }
    }
    ToolbarItem(placement: .confirmationAction) {
        Button("Done") { dismiss() }
    }
}
