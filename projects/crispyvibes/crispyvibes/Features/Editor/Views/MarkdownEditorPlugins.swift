import SwiftUI

struct EditorPluginContext {
    let viewModel: MarkdownViewModel
    let commandRequest: Binding<EditorCommandRequest?>
    let embeddedDropBridge: ContentViewerEmbeddedDropBridge?
}

@MainActor
private protocol EditorContentPlugin {
    var supportedTypes: Set<MarkdownViewModel.DocumentType> { get }
    func makeView(context: EditorPluginContext) -> AnyView
}

@MainActor
enum EditorPluginRegistry {
    private static let plugins: [any EditorContentPlugin] = [
        MarkupEditorPlugin(),
        PythonEditorPlugin(),
        JSONEditorPlugin(),
        RDocumentEditorPlugin(),
        PlainTextEditorPlugin(),
        ImagePreviewPlugin(),
        PDFPreviewPlugin(),
        OfficePreviewPlugin(),
        GitDiffPreviewPlugin()
    ]

    static func render(
        for documentType: MarkdownViewModel.DocumentType,
        context: EditorPluginContext
    ) -> AnyView? {
        guard let plugin = plugins.first(where: { $0.supportedTypes.contains(documentType) }) else {
            return nil
        }
        return plugin.makeView(context: context)
    }
}

@MainActor
private struct MarkupEditorPlugin: EditorContentPlugin {
    let supportedTypes: Set<MarkdownViewModel.DocumentType> = [.markdown, .html]

    func makeView(context: EditorPluginContext) -> AnyView {
        let viewModel = context.viewModel
        if viewModel.currentMarkupViewMode == .source {
            return sourceEditorView(for: viewModel, embeddedDropBridge: context.embeddedDropBridge)
        }

        let renderedMode: MarkupRenderedEditor.Mode = viewModel.documentType == .markdown ? .markdown : .html
        let renderedEditor = MarkupRenderedEditor(
            mode: renderedMode,
            baseDirectoryURL: viewModel.fileURL?.deletingLastPathComponent(),
            commandRequest: context.commandRequest.wrappedValue,
            isBufferLoading: viewModel.isBufferLoading,
            embeddedDropBridge: context.embeddedDropBridge,
            content: Binding(
                get: { viewModel.displayContent },
                set: { viewModel.userDidEdit($0) }
            )
        )
        .id("\(renderedMode == .markdown ? "markdown" : "html")-editor-\(viewModel.fileURL?.path ?? "")")
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        return AnyView(renderedEditor)
    }

    private func sourceEditorView(
        for viewModel: MarkdownViewModel,
        embeddedDropBridge: ContentViewerEmbeddedDropBridge?
    ) -> AnyView {
        let editor = CodeEditorView(
            fileURL: viewModel.fileURL ?? URL(fileURLWithPath: "/"),
            language: sourceLanguage(for: viewModel.documentType),
            embeddedDropBridge: embeddedDropBridge,
            pendingSourceSelection: pendingSourceSelection(for: viewModel),
            onPendingSourceSelectionConsumed: {
                viewModel.consumePendingSourceSelection(for: viewModel.currentDocumentID)
            },
            isBufferLoading: viewModel.isBufferLoading,
            content: Binding(
                get: { viewModel.displayContent },
                set: { _ in }
            ),
            onContentChange: { newContent in
                viewModel.userDidEdit(newContent)
            }
        )
        .id("markup-source-editor-\(viewModel.documentType == .markdown ? "markdown" : "html")-\(viewModel.fileURL?.path ?? "")")
        .accessibilityIdentifier("editor.code.markup.source")
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        return AnyView(editor)
    }

    private func sourceLanguage(for type: MarkdownViewModel.DocumentType) -> any LanguageDefinition {
        switch type {
        case .html:
            return GenericCodeLanguage(name: "HTML", fileExtensions: ["html", "htm"])
        default:
            return GenericCodeLanguage(name: "Markdown", fileExtensions: ["md", "markdown", "mdx"])
        }
    }
}

@MainActor
private struct PythonEditorPlugin: EditorContentPlugin {
    let supportedTypes: Set<MarkdownViewModel.DocumentType> = [.python]

    func makeView(context: EditorPluginContext) -> AnyView {
        let viewModel = context.viewModel
        let editor = VStack(spacing: 0) {
            PythonFileViewer(
                fileURL: viewModel.fileURL ?? URL(fileURLWithPath: "/"),
                isBufferLoading: viewModel.isBufferLoading,
                pendingSourceSelection: pendingSourceSelection(for: viewModel),
                onPendingSourceSelectionConsumed: {
                    viewModel.consumePendingSourceSelection(for: viewModel.currentDocumentID)
                },
                content: Binding(
                    get: { viewModel.displayContent },
                    set: { _ in }
                ),
                onContentChange: { newContent in
                    viewModel.userDidEdit(newContent)
                }
            )
        }
        .id("python-editor-\(viewModel.fileURL?.path ?? "")")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.code.python")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        return AnyView(editor)
    }
}

@MainActor
private struct JSONEditorPlugin: EditorContentPlugin {
    let supportedTypes: Set<MarkdownViewModel.DocumentType> = [.json]

    func makeView(context: EditorPluginContext) -> AnyView {
        let viewModel = context.viewModel
        let editor = VStack(spacing: 0) {
                CodeEditorView(
                                    fileURL: viewModel.fileURL ?? URL(fileURLWithPath: "/"),
                                    language: JSONLanguage(),
                                    codeEditorAccessibilityIdentifier: "editor.code.json",
                                    embeddedDropBridge: context.embeddedDropBridge,
                                    pendingSourceSelection: pendingSourceSelection(for: viewModel),
                                    onPendingSourceSelectionConsumed: {
                                        viewModel.consumePendingSourceSelection(for: viewModel.currentDocumentID)
                                    },
                                    isBufferLoading: viewModel.isBufferLoading,
                                    content: Binding(
                                        get: { viewModel.displayContent },
                                        set: { _ in }
                                ),
                                onContentChange: { newContent in
                                    viewModel.userDidEdit(newContent)
                                }
                            )
        }
        .id("json-editor-\(viewModel.fileURL?.path ?? "")")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.code.json")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        return AnyView(editor)
    }
}

@MainActor
private struct RDocumentEditorPlugin: EditorContentPlugin {
    let supportedTypes: Set<MarkdownViewModel.DocumentType> = [.r]

    func makeView(context: EditorPluginContext) -> AnyView {
        let viewModel = context.viewModel
        let editor = VStack(spacing: 0) {
                CodeEditorView(
                                    fileURL: viewModel.fileURL ?? URL(fileURLWithPath: "/"),
                                    language: RLanguage(),
                                    codeEditorAccessibilityIdentifier: "editor.code.r",
                                    embeddedDropBridge: context.embeddedDropBridge,
                                    pendingSourceSelection: pendingSourceSelection(for: viewModel),
                                    onPendingSourceSelectionConsumed: {
                                        viewModel.consumePendingSourceSelection(for: viewModel.currentDocumentID)
                                    },
                                    isBufferLoading: viewModel.isBufferLoading,
                                    content: Binding(
                                        get: { viewModel.displayContent },
                                        set: { _ in }
                                ),
                                onContentChange: { newContent in
                                    viewModel.userDidEdit(newContent)
                                }
                            )
        }
        .id("r-editor-\(viewModel.fileURL?.path ?? "")")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.code.r")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        return AnyView(editor)
    }
}

@MainActor
private struct PlainTextEditorPlugin: EditorContentPlugin {
    let supportedTypes: Set<MarkdownViewModel.DocumentType> = [.plainText]

    func makeView(context: EditorPluginContext) -> AnyView {
        let viewModel = context.viewModel

        if let language = viewModel.plainTextEditorLanguage {
            let identifier = "editor.code.\(viewModel.codeLanguageKind?.rawValue ?? "plain")"
            let editor = VStack(spacing: 0) {
                CodeEditorView(
                                    fileURL: viewModel.fileURL ?? URL(fileURLWithPath: "/"),
                                    language: language,
                                    codeEditorAccessibilityIdentifier: identifier,
                                    embeddedDropBridge: context.embeddedDropBridge,
                                    pendingSourceSelection: pendingSourceSelection(for: viewModel),
                                    onPendingSourceSelectionConsumed: {
                                        viewModel.consumePendingSourceSelection(for: viewModel.currentDocumentID)
                                    },
                                    isBufferLoading: viewModel.isBufferLoading,
                                    content: Binding(
                                        get: { viewModel.displayContent },
                                        set: { _ in }
                                    ),
                                onContentChange: { newContent in
                                    viewModel.userDidEdit(newContent)
                                }
                            )
            }
            .id("code-editor-\(viewModel.codeLanguageKind?.rawValue ?? "plain")-\(viewModel.fileURL?.path ?? "")")
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            return AnyView(editor)
        }

        let editor = PlainTextEditor(
            fileURL: viewModel.fileURL ?? URL(fileURLWithPath: "/"),
            embeddedDropBridge: context.embeddedDropBridge,
            pendingSourceSelection: pendingSourceSelection(for: viewModel),
            onPendingSourceSelectionConsumed: {
                viewModel.consumePendingSourceSelection(for: viewModel.currentDocumentID)
            },
            isBufferLoading: viewModel.isBufferLoading,
            content: Binding(
                get: { viewModel.displayContent },
                set: { _ in }
            ),
            onContentChange: { newContent in
                viewModel.userDidEdit(newContent)
            }
        )
        .id("plaintext-editor-\(viewModel.fileURL?.path ?? "")")
        .accessibilityIdentifier("editor.plaintext")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        return AnyView(editor)
    }
}

@MainActor
private struct ImagePreviewPlugin: EditorContentPlugin {
    let supportedTypes: Set<MarkdownViewModel.DocumentType> = [.image]

    func makeView(context: EditorPluginContext) -> AnyView {
        guard let fileURL = context.viewModel.imageFileURL else {
            return AnyView(previewUnavailableView())
        }

        let preview = ImageFilePreview(
            fileURL: fileURL,
            onSaveDataRequest: { renderedFileURL, data, completion in
                context.viewModel.saveImagePreviewData(data, from: renderedFileURL, completion: completion)
            },
            onRasterDirtyStateChange: { hasUnsavedEdits in
                context.viewModel.setImageEditDirtyState(hasUnsavedEdits)
            }
        )
        .accessibilityIdentifier("editor.preview.image.host")
        return AnyView(preview)
    }
}

@MainActor
private struct PDFPreviewPlugin: EditorContentPlugin {
    let supportedTypes: Set<MarkdownViewModel.DocumentType> = [.pdf]

    func makeView(context: EditorPluginContext) -> AnyView {
        guard let fileURL = context.viewModel.pdfFileURL else {
            return AnyView(previewUnavailableView())
        }

        return AnyView(
            PDFFilePreview(fileURL: fileURL)
                .accessibilityIdentifier("editor.preview.pdf.host")
        )
    }
}

@MainActor
private struct OfficePreviewPlugin: EditorContentPlugin {
    let supportedTypes: Set<MarkdownViewModel.DocumentType> = [.office]

    func makeView(context: EditorPluginContext) -> AnyView {
        guard let fileURL = context.viewModel.officeFileURL else {
            return AnyView(previewUnavailableView())
        }

        return AnyView(
            OfficeFilePreview(fileURL: fileURL)
                .accessibilityIdentifier("editor.preview.office.host")
        )
    }
}

@MainActor
private struct GitDiffPreviewPlugin: EditorContentPlugin {
    let supportedTypes: Set<MarkdownViewModel.DocumentType> = [.gitDiff]

    func makeView(context: EditorPluginContext) -> AnyView {
        AnyView(
            GitDiffPreview(content: context.viewModel.rawContent)
                .accessibilityIdentifier("editor.preview.gitdiff")
        )
    }
}

private func previewUnavailableView() -> some View {
    ContentUnavailableView(
        "Preview Unavailable",
        systemImage: "eye.slash",
        description: Text(AppStrings.Editor.cannotPreview)
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

@MainActor
private func pendingSourceSelection(for viewModel: MarkdownViewModel) -> MarkdownViewModel.SourceSelection? {
    guard let documentID = viewModel.currentDocumentID else { return nil }
    guard viewModel.pendingSourceSelection?.documentID == documentID else { return nil }
    return viewModel.pendingSourceSelection?.selection
}
