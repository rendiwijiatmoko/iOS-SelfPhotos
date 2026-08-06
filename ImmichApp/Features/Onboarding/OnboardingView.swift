import SwiftUI

/// Layar masuk: alamat server dan kredensial dalam SATU halaman.
///
/// Sebelumnya dua langkah berurutan. Memisahkannya tidak memberi apa pun kepada
/// pengguna — keduanya sama-sama harus benar sebelum ada yang terjadi — dan
/// justru menambah satu ketukan serta satu layar yang harus di-"Back".
struct OnboardingView: View {
    @Environment(SessionManager.self) private var session
    @State private var vm: OnboardingViewModel?

    var body: some View {
        Group {
            if let vm {
                form(vm)
            } else {
                Color.clear.onAppear { vm = OnboardingViewModel(session: session) }
            }
        }
    }

    private func form(_ vm: OnboardingViewModel) -> some View {
        @Bindable var vm = vm

        return ScrollView {
            VStack(spacing: 28) {
                masthead
                serverField(vm)
                credentials(vm)
                submitArea(vm)
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 32)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        // Kolom terakhir tidak boleh tertutup papan ketik pada layar pendek.
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Kepala

    private var masthead: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Immich")
                .font(.largeTitle.bold())

            Text("Sign in to your own photo server.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Kolom

    private func serverField(_ vm: OnboardingViewModel) -> some View {
        @Bindable var vm = vm

        return field("Server") {
            TextField("https://immich.example.com", text: $vm.serverText)
                .textInputAutocapitalization(.never)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .submitLabel(.next)
        }
    }

    @ViewBuilder
    private func credentials(_ vm: OnboardingViewModel) -> some View {
        @Bindable var vm = vm

        VStack(spacing: 16) {
            methodPicker(vm)

            switch vm.method {
            case .password:
                field("Email") {
                    TextField("you@example.com", text: $vm.email)
                        .textInputAutocapitalization(.never)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                }
                field("Password") {
                    SecureField("Required", text: $vm.password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit { Task { await vm.submit() } }
                }

            case .apiKey:
                field("API Key") {
                    SecureField("Required", text: $vm.apiKey)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit { Task { await vm.submit() } }
                }
                Text("Generate an API key in your Immich account settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// API Key selalu tersedia — justru di server OAuth-only, tempat login kata
    /// sandi dimatikan, itulah satu-satunya cara masuk.
    private func methodPicker(_ vm: OnboardingViewModel) -> some View {
        @Bindable var vm = vm

        return Picker("Sign in with", selection: $vm.method) {
            if vm.features?.passwordLogin != false {
                Text("Email").tag(OnboardingViewModel.Method.password)
            }
            Text("API Key").tag(OnboardingViewModel.Method.apiKey)
        }
        .pickerStyle(.segmented)
        .onChange(of: vm.features?.passwordLogin) { _, enabled in
            if enabled == false { vm.method = .apiKey }
        }
    }

    /// Label kecil di atas kolom, bukan placeholder di dalamnya: placeholder
    /// hilang begitu diketik, dan pengguna kehilangan penanda kolom mana itu.
    private func field<Content: View>(
        _ label: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.fill.quaternary, in: .rect(cornerRadius: 12))
        }
    }

    // MARK: - Kirim

    @ViewBuilder
    private func submitArea(_ vm: OnboardingViewModel) -> some View {
        VStack(spacing: 12) {
            if case .failed(let message) = vm.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await vm.submit() }
            } label: {
                Group {
                    if vm.phase.isLoading {
                        ProgressView()
                    } else {
                        Text("Sign In")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 22)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!vm.canSubmit || vm.phase.isLoading)
        }
    }
}

#Preview {
    OnboardingView()
        .environment(SessionManager())
}
