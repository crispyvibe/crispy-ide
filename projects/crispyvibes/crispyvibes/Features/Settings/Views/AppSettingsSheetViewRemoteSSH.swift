import SwiftUI

extension AppSettingsSheetView {
    var remoteSSHCategoryContent: some View {
        RemoteSSHSettingsContent()
    }
}

private struct RemoteSSHSettingsContent: View {
    @StateObject private var profileStore = SSHProfileStore()
    @StateObject private var testVM = SSHProfileTestViewModel()
    @State private var isShowingConnectionSheet = false
    @State private var editingProfile: SSHConnectionProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            connectionProfilesSection
        }
    }

    private var connectionProfilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SSH Connection Profiles").font(AppTypographyTokens.subheadlineSemibold)
                Spacer()
                Button("Import from SSH Config") { importFromSSHConfig() }.controlSize(.small)
                Button { editingProfile = nil; isShowingConnectionSheet = true } label: {
                    Image(systemName: "plus")
                }.controlSize(.small)
            }

            if profileStore.profiles.isEmpty {
                Text("No connection profiles configured.")
                    .font(AppTypographyTokens.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 20)
            } else {
                ForEach(profileStore.profiles) { profile in
                    SSHProfileRow(
                        profile: profile,
                        profileStore: profileStore,
                        testVM: testVM,
                        onEdit: { editingProfile = profile; isShowingConnectionSheet = true },
                        onDelete: { profileStore.remove(id: profile.id) }
                    )
                }
            }
        }
        .sheet(isPresented: $isShowingConnectionSheet) {
            SSHConnectionSheet(
                profile: editingProfile,
                onSave: { profile in
                    if editingProfile != nil { profileStore.update(profile) } else { profileStore.add(profile) }
                    isShowingConnectionSheet = false
                    testVM.validateKey(for: profile)
                },
                onCancel: { isShowingConnectionSheet = false }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { testVM.pendingHostKeyProfile != nil },
                set: { presented in
                    if !presented {
                        testVM.rejectHostKey()
                    }
                }
            )
        ) {
            SSHHostKeyPromptView(
                host: testVM.pendingHostKeyProfile?.host ?? "",
                fingerprint: testVM.pendingHostKeyFingerprint ?? "Unable to fetch fingerprint",
                onAccept: { testVM.acceptHostKeyAndContinue() },
                onReject: { testVM.rejectHostKey() }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { testVM.generatedPublicKey != nil },
                set: { presented in
                    if !presented {
                        testVM.dismissPublicKey()
                    }
                }
            )
        ) {
            GeneratedSSHKeySheet(
                publicKey: testVM.generatedPublicKey ?? "",
                onClose: { testVM.dismissPublicKey() }
            )
        }
    }

    private func importFromSSHConfig() {
        for host in SSHConfigParser.parse() {
            let profile = SSHConfigParser.toProfile(host)
            if !profileStore.profiles.contains(where: { $0.host == profile.host && $0.user == profile.user }) {
                profileStore.add(profile)
                testVM.validateKey(for: profile)
            }
        }
    }
}

private struct GeneratedSSHKeySheet: View {
    let publicKey: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundStyle(.green)
                Text("Ed25519 Key Generated")
                    .font(AppTypographyTokens.headline)
            }

            Text("Add this public key to the remote machine's `~/.ssh/authorized_keys`, then test the connection again.")
                .font(AppTypographyTokens.callout)

            ScrollView {
                Text(publicKey)
                    .font(AppTypographyTokens.captionMonospaced)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 180)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Spacer()
                Button("Close") { onClose() }
                    .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
