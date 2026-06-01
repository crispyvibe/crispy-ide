// SSHConnectionSheet.swift — SSH Remote Development

import SwiftUI
import UniformTypeIdentifiers

/// Sheet for creating or editing an SSH connection profile.
struct SSHConnectionSheet: View {
    let profile: SSHConnectionProfile?
    let onSave: (SSHConnectionProfile) -> Void
    let onCancel: () -> Void

    @StateObject private var vm = SSHConnectionSheetViewModel()
    @State private var isShowingFilePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(profile == nil ? "New SSH Connection" : "Edit SSH Connection").font(AppTypographyTokens.headline)

            VStack(alignment: .leading, spacing: 12) {
                field("Display Name", text: $vm.displayName, placeholder: "My Server")
                field("Host", text: $vm.host, placeholder: "192.168.1.100 or myserver.com")
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Port").font(AppTypographyTokens.caption).foregroundStyle(.secondary)
                        TextField("22", text: $vm.port).textFieldStyle(.roundedBorder).frame(width: 72)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("User").font(AppTypographyTokens.caption).foregroundStyle(.secondary)
                        TextField("username", text: $vm.user).textFieldStyle(.roundedBorder)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Authentication").font(AppTypographyTokens.subheadlineSemibold)
                Picker("", selection: $vm.useKeyFile) {
                    Text("SSH Agent (default keys)").tag(false)
                    Text("Specific Key File").tag(true)
                }.pickerStyle(.segmented).labelsHidden()

                if vm.useKeyFile {
                    HStack(spacing: 8) {
                        TextField("~/.ssh/id_ed25519", text: $vm.keyFilePath)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: vm.keyFilePath) { _, _ in vm.validateKey() }
                        Button("Browse…") { isShowingFilePicker = true }.controlSize(.small)
                    }
                    keyValidationFeedback
                } else {
                    Text("Will try ~/.ssh/id_ed25519, id_ecdsa in order.")
                        .font(AppTypographyTokens.caption).foregroundStyle(.secondary)
                }
            }

            Divider()

            Toggle(isOn: $vm.agentCLIEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow Agent CLI (crispy) on this connection")
                        .font(AppTypographyTokens.subheadlineSemibold)
                    Text("Lets agents and terminals on this host control the IDE via the bundled crispy command. Turn off for shared or untrusted hosts.")
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Spacer().frame(height: 4)

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }.keyboardShortcut(.escape, modifiers: [])
                Button("Save") {
                    onSave(vm.buildProfile(existingID: profile?.id, importedFromConfig: profile?.importedFromConfig ?? false))
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!vm.isValid)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { vm.load(from: profile); if vm.useKeyFile { vm.validateKey() } }
        .fileImporter(isPresented: $isShowingFilePicker, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first { vm.keyFilePath = url.path; vm.validateKey() }
        }
    }

    @ViewBuilder
    private var keyValidationFeedback: some View {
        switch vm.keyValidationStatus {
        case .none: EmptyView()
        case .checking: HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Checking key…").font(AppTypographyTokens.caption) }
        case .valid(let desc): HStack(spacing: 4) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(desc).font(AppTypographyTokens.caption) }
        case .invalid(let msg): HStack(spacing: 4) { Image(systemName: "xmark.circle.fill").foregroundStyle(.red); Text(msg).font(AppTypographyTokens.caption).foregroundStyle(.red) }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(AppTypographyTokens.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }
}
