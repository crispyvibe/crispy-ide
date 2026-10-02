import SwiftUI

/// Resize dialog: pixel width/height with optional proportional lock.
@MainActor
struct RasterImageResizeSheet: View {
    @ObservedObject var viewModel: RasterImageEditorViewModel
    @State private var width = 0
    @State private var height = 0
    @State private var keepsProportions = true
    @Environment(\.dismiss) private var dismiss

    private var currentSize: CGSize {
        viewModel.canvasState.imagePixelSize ?? CGSize(width: 1, height: 1)
    }

    private var isValid: Bool {
        (1...RasterImageEditorViewModel.maximumPixelEdge).contains(width) &&
            (1...RasterImageEditorViewModel.maximumPixelEdge).contains(height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.ImageEditor.resizeTitle).font(.headline)
            Text(AppStrings.ImageEditor.resizeCurrent(width: Int(currentSize.width), height: Int(currentSize.height)))
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text(AppStrings.ImageEditor.resizeWidth)
                    TextField(AppStrings.ImageEditor.resizeWidth, value: widthBinding, format: .number)
                        .frame(width: 90)
                        .accessibilityIdentifier("editor.preview.image.resize.width")
                    Text(AppStrings.ImageEditor.resizePixels).foregroundStyle(.secondary)
                }
                GridRow {
                    Text(AppStrings.ImageEditor.resizeHeight)
                    TextField(AppStrings.ImageEditor.resizeHeight, value: heightBinding, format: .number)
                        .frame(width: 90)
                        .accessibilityIdentifier("editor.preview.image.resize.height")
                    Text(AppStrings.ImageEditor.resizePixels).foregroundStyle(.secondary)
                }
            }
            .textFieldStyle(.roundedBorder)
            Toggle(AppStrings.ImageEditor.resizeKeepProportions, isOn: $keepsProportions)
                .accessibilityIdentifier("editor.preview.image.resize.keep-proportions")
            HStack {
                ForEach([25, 50, 75, 200], id: \.self) { percent in
                    Button(AppStrings.ImageEditor.percent(Double(percent) / 100)) { applyPercent(percent) }
                }
                Spacer()
                Button(AppStrings.ImageEditor.cancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(AppStrings.ImageEditor.resizeApply) {
                    viewModel.resize(toPixelWidth: width, height: height)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
                .accessibilityIdentifier("editor.preview.image.resize.apply")
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            width = Int(currentSize.width)
            height = Int(currentSize.height)
        }
    }

    private var widthBinding: Binding<Int> {
        Binding(get: { width }, set: { newValue in
            width = newValue
            if keepsProportions, currentSize.width > 0 {
                height = max(Int((CGFloat(newValue) * currentSize.height / currentSize.width).rounded()), 1)
            }
        })
    }

    private var heightBinding: Binding<Int> {
        Binding(get: { height }, set: { newValue in
            height = newValue
            if keepsProportions, currentSize.height > 0 {
                width = max(Int((CGFloat(newValue) * currentSize.width / currentSize.height).rounded()), 1)
            }
        })
    }

    private func applyPercent(_ percent: Int) {
        width = max(Int((currentSize.width * CGFloat(percent) / 100).rounded()), 1)
        height = max(Int((currentSize.height * CGFloat(percent) / 100).rounded()), 1)
    }
}

/// Export As dialog: format and quality, then a save panel for the destination.
@MainActor
struct RasterImageExportSheet: View {
    @ObservedObject var viewModel: RasterImageEditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.ImageEditor.exportTitle).font(.headline)
            if let size = viewModel.canvasState.imagePixelSize {
                Text(AppStrings.ImageEditor.resizeCurrent(width: Int(size.width), height: Int(size.height)))
                    .foregroundStyle(.secondary)
            }
            Picker(AppStrings.ImageEditor.exportFormat, selection: $viewModel.exportOptions.format) {
                ForEach(RasterImageExportFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .accessibilityIdentifier("editor.preview.image.export.format")
            if viewModel.exportOptions.format.isLossy {
                HStack {
                    Text(AppStrings.ImageEditor.exportQuality)
                    Slider(value: $viewModel.exportOptions.quality, in: 0.1...1)
                        .accessibilityIdentifier("editor.preview.image.export.quality")
                    Text(AppStrings.ImageEditor.percent(viewModel.exportOptions.quality))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            if !viewModel.exportOptions.format.supportsAlpha {
                Text(AppStrings.ImageEditor.exportDropsTransparency)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(AppStrings.ImageEditor.cancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(AppStrings.ImageEditor.exportChooseLocation) { viewModel.exportAs() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("editor.preview.image.export.choose")
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
