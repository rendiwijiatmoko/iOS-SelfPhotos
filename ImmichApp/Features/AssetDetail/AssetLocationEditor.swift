import MapKit
import SwiftUI

/// Sheet untuk mengubah lokasi foto.
///
/// Peta digeser, pin tetap di tengah — koordinat yang disimpan adalah titik
/// tengah peta saat itu. Pola ini menghindari kebutuhan gesture tap/drag
/// khusus dan bekerja mulus dengan pan & zoom bawaan MapKit.
struct AssetLocationEditor: View {
    let initialCoordinate: CLLocationCoordinate2D?
    var onSave: (CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    @State private var center: CLLocationCoordinate2D

    /// Dipakai kalau foto belum punya koordinat sama sekali.
    private static let fallback = CLLocationCoordinate2D(
        latitude: -6.2, longitude: 106.816666)

    init(
        initialCoordinate: CLLocationCoordinate2D?,
        onSave: @escaping (CLLocationCoordinate2D) -> Void
    ) {
        self.initialCoordinate = initialCoordinate
        self.onSave = onSave

        let start = initialCoordinate ?? Self.fallback
        _center = State(initialValue: start)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: start,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))))
    }

    var body: some View {
        NavigationStack {
            map
                .overlay(alignment: .center) { centerPin }
                .safeAreaInset(edge: .bottom) { coordinateLabel }
                .navigationTitle("Adjust Location")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave(center)
                            dismiss()
                        }
                    }
                }
        }
    }

    private var map: some View {
        Map(position: $position)
            .mapStyle(.standard)
            .onMapCameraChange(frequency: .continuous) { context in
                center = context.region.center
            }
            .ignoresSafeArea(edges: .bottom)
    }

    /// Offset ke atas setengah tinggi pin supaya ujung runcingnya, bukan
    /// tengahnya, yang menunjuk titik tengah peta.
    private var centerPin: some View {
        Image(systemName: "mappin")
            .font(.title)
            .foregroundStyle(.red)
            .shadow(radius: 2)
            .offset(y: -14)
            .allowsHitTesting(false)
    }

    private var coordinateLabel: some View {
        Text(String(format: "%.5f, %.5f", center.latitude, center.longitude))
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.bar)
    }
}
