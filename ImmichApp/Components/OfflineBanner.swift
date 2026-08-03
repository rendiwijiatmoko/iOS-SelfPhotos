import SwiftUI

struct OfflineBanner: View {
    let isOnline: Bool

    var body: some View {
        if !isOnline {
            HStack {
                Image(systemName: "wifi.slash")
                Text("Offline Mode - Showing Cached Photos")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(.orange.opacity(0.1))
            .foregroundStyle(.orange)
        }
    }
}

#Preview {
    OfflineBanner(isOnline: false)
}
