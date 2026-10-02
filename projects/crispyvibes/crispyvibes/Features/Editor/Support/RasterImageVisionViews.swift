import SwiftUI

/// Toolbar menu for on-device Vision features.
@MainActor
struct RasterImageVisionMenu: View {
    @ObservedObject var viewModel: RasterImageEditorViewModel

    var body: some View {
        Menu {
            Button(AppStrings.ImageEditor.recognizeText, systemImage: "text.viewfinder") { viewModel.recognizeText() }
                .accessibilityIdentifier("editor.preview.image.vision.text")
            Button(AppStrings.ImageEditor.removeBackground, systemImage: "person.crop.rectangle") { viewModel.removeBackground() }
                .accessibilityIdentifier("editor.preview.image.vision.background")
            if !viewModel.recognizedText.isEmpty {
                Divider()
                Button(AppStrings.ImageEditor.showRecognizedText) { viewModel.isRecognizedTextPresented = true }
                Button(AppStrings.ImageEditor.copyAllText) { viewModel.copyRecognizedText() }
            }
        } label: {
            Label(AppStrings.ImageEditor.smartTools, systemImage: viewModel.isAnalyzing ? "hourglass" : "wand.and.stars")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(AppStrings.ImageEditor.smartTools)
        .disabled(!viewModel.canAnalyze)
        .accessibilityLabel(AppStrings.ImageEditor.smartTools)
        .accessibilityIdentifier("editor.preview.image.vision")
    }
}

/// Recognized text: selectable list, per-line copy, and Copy All.
@MainActor
struct RasterImageRecognizedTextSheet: View {
    @ObservedObject var viewModel: RasterImageEditorViewModel
    @State private var selection = Set<RecognizedTextLine.ID>()
    @Environment(\.dismiss) private var dismiss

    private var selectedLines: [RecognizedTextLine] {
        viewModel.recognizedText.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.ImageEditor.recognizedTextTitle).font(.headline)
            List(viewModel.recognizedText, selection: $selection) { line in
                Text(line.text)
                    .textSelection(.enabled)
                    .contextMenu {
                        Button(AppStrings.ImageEditor.copy) { viewModel.copyRecognizedText([line]) }
                    }
            }
            .frame(minHeight: 200)
            .accessibilityIdentifier("editor.preview.image.vision.text.list")
            HStack {
                Button(AppStrings.ImageEditor.copySelectedText) { viewModel.copyRecognizedText(selectedLines) }
                    .disabled(selection.isEmpty)
                Spacer()
                Button(AppStrings.ImageEditor.done) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(AppStrings.ImageEditor.copyAllText) { viewModel.copyRecognizedText() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("editor.preview.image.vision.text.copy-all")
            }
        }
        .padding(20)
        .frame(width: 460, height: 380)
    }
}
