import SwiftUI
import PhotosUI

struct BackupView: View {
    @Environment(SessionManager.self) private var session
    @State private var vm: BackupViewModel?

    var body: some View {
        content
            .navigationTitle("Backup")
        .task {
            if vm == nil {
                let api = APIClient(session: session)
                let repo = BackupRepository(api: api)
                vm = BackupViewModel(repo: repo, dataManager: SwiftDataManager.shared)
            }
            await vm?.loadStorageInfo()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let vm {
            switch vm.phase {
            case .idle:
                backupOptions(vm)

            case .loading:
                uploadProgress(vm)

            case .loaded:
                uploadSummary(vm)

            case .failed(let error):
                errorState(error, vm)
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func backupOptions(_ vm: BackupViewModel) -> some View {
        List {
            Section("Storage") {
                if let storage = vm.storageInfo {
                    LabeledContent("Used", value: storage.diskUse ?? formatBytes(storage.diskUseRaw ?? 0))
                    LabeledContent("Total", value: storage.diskSize ?? formatBytes(storage.diskSizeRaw ?? 0))
                }
            }

            Section("Upload") {
                PhotosPicker(
                    selection: Binding(
                        get: { vm.selectedPhotos },
                        set: { vm.selectedPhotos = $0 }
                    ),
                    matching: .images
                ) {
                    Text("Select Photos to Upload")
                }

                if !vm.selectedPhotos.isEmpty {
                    Text("\(vm.selectedPhotos.count) photo(s) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Upload") {
                        Task {
                            await vm.uploadSelectedPhotos()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }

            Section("Info") {
                Text("Selected photos will be uploaded to your server. Duplicates will be skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func uploadProgress(_ vm: BackupViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Text("Uploading Photos")
                    .font(.headline)

                ProgressView(value: vm.uploadProgress)
                    .frame(height: 8)

                Text("\(vm.currentUploadIndex) / \(vm.totalUploads)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.gray.opacity(0.1))
            .cornerRadius(8)

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func uploadSummary(_ vm: BackupViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: vm.failedUploads.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(vm.failedUploads.isEmpty ? .green : .orange)

                Text("Upload Complete")
                    .font(.headline)

                VStack(spacing: 8) {
                    HStack {
                        Text("Successful:")
                        Spacer()
                        Text("\(vm.successCount)")
                            .fontWeight(.semibold)
                    }

                    if vm.skippedCount > 0 {
                        HStack {
                            Text("Skipped (duplicates):")
                            Spacer()
                            Text("\(vm.skippedCount)")
                                .fontWeight(.semibold)
                        }
                    }

                    if !vm.failedUploads.isEmpty {
                        HStack {
                            Text("Failed:")
                            Spacer()
                            Text("\(vm.failedUploads.count)")
                                .fontWeight(.semibold)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") {
                vm.reset()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    @ViewBuilder
    private func errorState(_ error: String, _ vm: BackupViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Upload Failed")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Try Again") {
                vm.reset()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

#Preview {
    BackupView()
        .environment(SessionManager())
}
