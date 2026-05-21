// RemoteFileBrowserView.swift — SSH Remote Development

import SwiftUI

/// Browses remote directories via SFTP for folder selection.
struct RemoteFileBrowserView: View {
    @Environment(\.crispyvibesUIScale) private var uiScale

    let connection: SSHConnection
    let onSelect: (String) -> Void
    let onBack: () -> Void

    @State private var currentPath = "~"
    @State private var entries: [FileItemDescriptor] = []
    @State private var isLoading = false
    @State private var error: String?

    private var fileSystem: SFTPFileSystemProvider { SFTPFileSystemProvider(connection: connection) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { onBack() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).controlSize(.small)
                Text(connection.profile.displayName).font(AppTypographyTokens.subheadlineSemibold)
                Spacer()
                Button("Select This Folder") { onSelect(currentPath) }.controlSize(.small)
            }

            HStack {
                Image(systemName: "folder")
                Text(currentPath).font(AppTypographyTokens.captionMonospaced).lineLimit(1).truncationMode(.middle)
            }.foregroundStyle(.secondary)

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, alignment: .center).padding()
            } else if let error {
                Text(error).foregroundStyle(.red).font(AppTypographyTokens.caption)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if currentPath != "/" && currentPath != "~" {
                            Button { navigateUp() } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up")
                                        .font(AppTypographyTokens.scaledIcon(13))
                                        .frame(width: uiScale.iconSize(16))
                                    Text("..").font(AppTypographyTokens.callout)
                                }.padding(.vertical, 3)
                            }.buttonStyle(.plain)
                        }

                        ForEach(entries.filter(\.isDirectory), id: \.path) { entry in
                            Button { navigate(to: entry.path) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                        .font(AppTypographyTokens.scaledIcon(13))
                                        .frame(width: uiScale.iconSize(16))
                                    Text(entry.name).font(AppTypographyTokens.callout).lineLimit(1)
                                }.padding(.vertical, 3)
                            }.buttonStyle(.plain)
                        }

                        ForEach(entries.filter { !$0.isDirectory }, id: \.path) { entry in
                            HStack(spacing: 6) {
                                Image(systemName: "doc")
                                    .font(AppTypographyTokens.scaledIcon(13))
                                    .frame(width: uiScale.iconSize(16))
                                Text(entry.name).font(AppTypographyTokens.callout).lineLimit(1).foregroundStyle(.secondary)
                            }.padding(.vertical, 3)
                        }
                    }
                }.frame(maxHeight: 300)
            }
        }
        .task { await loadDirectory() }
    }

    private func navigate(to path: String) {
        currentPath = path
        Task { await loadDirectory() }
    }

    private func navigateUp() {
        currentPath = (currentPath as NSString).deletingLastPathComponent
        Task { await loadDirectory() }
    }

    private func loadDirectory() async {
        isLoading = true; error = nil
        do {
            if currentPath == "~" {
                if let sftp = try? connection.availableSFTP(),
                   let home = try? sftp.homeDirectory(), !home.isEmpty {
                    currentPath = home
                }
            }
            entries = try await fileSystem.contentsOfDirectory(at: currentPath)
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }
}
