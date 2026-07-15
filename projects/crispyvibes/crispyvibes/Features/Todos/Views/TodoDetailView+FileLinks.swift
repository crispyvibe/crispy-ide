import SwiftUI
import UniformTypeIdentifiers

// F060 — file links on the todo detail pane (R01/R02): chips that open the
// live file in the content viewer (line-anchored when set), a drop target for
// adding links, and a missing state for dangling paths. Links are references,
// never copies; deleting a chip never touches the file.

extension TodoDetailView {

    @ViewBuilder var fileLinksSection: some View {
        let links = store.fileLinks(forTodo: todo.id)
        if !links.isEmpty || isDropTargetedForLinks {
            VStack(alignment: .leading, spacing: uiScale.spacing(6)) {
                sectionLabel(AppStrings.TodoPipeline.filesLabel)
                FlowLayoutCompat(spacing: uiScale.spacing(6)) {
                    ForEach(links) { link in
                        fileLinkChip(link)
                    }
                }
            }
        }
    }

    @ViewBuilder private func fileLinkChip(_ link: TodoFileLink) -> some View {
        let missing = !FileManager.default.fileExists(atPath: link.path)
        let external = !isInsideAnyProject(link.path)
        HStack(spacing: uiScale.spacing(4)) {
            Image(systemName: missing ? "questionmark.folder" : "doc")
                .font(.system(size: uiScale.iconSize(9)))
            Text(link.displayName)
                .font(.system(size: uiScale.textSize(10), weight: .medium))
                .lineLimit(1)
                .strikethrough(missing, color: palette.tertiaryTextColor)
            if external, !missing {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: uiScale.iconSize(8)))
                    .foregroundStyle(palette.tertiaryTextColor)
                    .help(AppStrings.TodoPipeline.externalFileHint)
            }
        }
        .foregroundStyle(missing ? palette.tertiaryTextColor : palette.secondaryTextColor)
        .padding(.horizontal, uiScale.spacing(7))
        .padding(.vertical, uiScale.spacing(3))
        .background(
            (missing ? palette.errorColor : palette.borderColorValue).opacity(missing ? 0.10 : 0.15),
            in: Capsule()
        )
        .contentShape(Capsule())
        .onTapGesture {
            guard !missing else { return }
            onOpenFile?(link.path, link.line)
        }
        .help(missing
              ? "\(AppStrings.TodoPipeline.missingFileHint): \(link.path)"
              : link.path)
        .contextMenu {
            if !missing {
                Button(AppStrings.TodoPipeline.openFile) { onOpenFile?(link.path, link.line) }
            }
            Button(role: .destructive) {
                Task { await store.removeFileLink(todoID: todo.id, path: link.path) }
            } label: {
                Label(AppStrings.TodoPipeline.removeLink, systemImage: "trash")
            }
        }
    }

    /// Drop handler for the whole detail pane: dropped files become links.
    func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let path = url.standardizedFileURL.path
                let todoID = todo.id
                Task { @MainActor in
                    _ = await store.addFileLink(todoID: todoID, path: path)
                }
            }
        }
        return accepted
    }

    private func isInsideAnyProject(_ path: String) -> Bool {
        guard let root = todo.projectPath ?? focusedProjectPath else { return false }
        return path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}

/// Minimal wrapping layout for chips (macOS 13+: Layout protocol).
struct FlowLayoutCompat: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
