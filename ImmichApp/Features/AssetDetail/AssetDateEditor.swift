import SwiftUI

/// Sheet untuk mengubah tanggal & waktu pengambilan foto.
struct AssetDateEditor: View {
    let initialDate: Date
    var onSave: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(initialDate: Date, onSave: @escaping (Date) -> Void) {
        self.initialDate = initialDate
        self.onSave = onSave
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Date & Time",
                    selection: $date,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
            }
            .navigationTitle("Adjust Date & Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(date)
                        dismiss()
                    }
                    .disabled(date == initialDate)
                }
            }
        }
    }
}
