import SwiftUI

struct OnboardingView: View {
    @Environment(SessionManager.self) private var session
    @State private var vm: OnboardingViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm {
                    content(vm)
                } else {
                    ProgressView()
                        .onAppear { vm = OnboardingViewModel(session: session) }
                }
            }
            .navigationTitle("Immich")
        }
    }

    @ViewBuilder
    private func content(_ vm: OnboardingViewModel) -> some View {
        @Bindable var vm = vm

        VStack(spacing: 24) {
            switch vm.step {
            case .server:
                serverStep(vm)
            case .login:
                loginStep(vm)
            }

            Spacer()

            if case .loading = vm.phase {
                ProgressView()
            }

            if case .failed(let msg) = vm.phase {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private func serverStep(_ vm: OnboardingViewModel) -> some View {
        @Bindable var vm = vm

        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Server Address")
                    .font(.headline)
                Text("Enter your Immich server URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("https://immich.example.com", text: $vm.serverText)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            Button("Connect") {
                Task { await vm.connect() }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(vm.serverText.isEmpty || vm.phase.isLoading)
        }
    }

    @ViewBuilder
    private func loginStep(_ vm: OnboardingViewModel) -> some View {
        @Bindable var vm = vm

        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sign In")
                    .font(.headline)
                Text("Enter your credentials")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Login Method", selection: $vm.showApiKeyTab) {
                Text("Email").tag(false)
                if vm.features?.passwordLogin == true {
                    Text("API Key").tag(true)
                }
            }
            .pickerStyle(.segmented)

            if !vm.showApiKeyTab {
                emailPasswordForm(vm)
            } else {
                apiKeyForm(vm)
            }

            Button("Back") {
                vm.reset()
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func emailPasswordForm(_ vm: OnboardingViewModel) -> some View {
        @Bindable var vm = vm

        VStack(spacing: 12) {
            TextField("Email", text: $vm.email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            SecureField("Password", text: $vm.password)
                .textFieldStyle(.roundedBorder)

            Button("Sign In") {
                Task { await vm.loginPassword() }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(vm.email.isEmpty || vm.password.isEmpty || vm.phase.isLoading)
        }
    }

    @ViewBuilder
    private func apiKeyForm(_ vm: OnboardingViewModel) -> some View {
        @Bindable var vm = vm

        VStack(spacing: 12) {
            SecureField("API Key", text: $vm.apiKey)
                .textFieldStyle(.roundedBorder)

            Text("Generate API key in your Immich settings")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Sign In with API Key") {
                Task { await vm.loginApiKey() }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(vm.apiKey.isEmpty || vm.phase.isLoading)
        }
    }
}

#Preview {
    OnboardingView()
        .environment(SessionManager())
}
