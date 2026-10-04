import AppKit
import SwiftUI

/// Markup mode controls: tool palette and style/text inspector for new or selected items.
@MainActor
struct RasterImageMarkupToolbar: View {
    @ObservedObject var viewModel: RasterImageEditorViewModel
    var accessibilityPrefix = "editor.preview.image"
    @FocusState private var isTextFieldFocused: Bool

    private static let fontFamilies: [String] = {
        ["System"] + NSFontManager.shared.availableFontFamilies.sorted()
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            toolPalette
            inspector
        }
        .onChange(of: viewModel.textFocusRequest) { _, _ in isTextFieldFocused = true }
    }

    private var toolPalette: some View {
        HStack(spacing: 2) {
            ForEach(RasterMarkupTool.allCases) { tool in
                Button(tool.title, systemImage: tool.systemImage) { viewModel.selectMarkupTool(tool) }
                    .labelStyle(.iconOnly)
                    .help(tool.title)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(viewModel.markupTool == tool ? Color.accentColor.opacity(0.25) : Color.clear)
                    )
                    .accessibilityAddTraits(viewModel.markupTool == tool ? .isSelected : [])
                    .accessibilityIdentifier("\(accessibilityPrefix).tool.\(tool.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppStrings.ImageEditor.markupTools)
    }

    private var inspector: some View {
        HStack(spacing: 10) {
            ColorPicker(AppStrings.ImageEditor.strokeColor, selection: Binding(
                get: { Color(nsColor: viewModel.markupStyle.strokeColor.nsColor) },
                set: { viewModel.setStrokeColor(RasterColor(NSColor($0))) }
            ), supportsOpacity: true)
            .fixedSize()
            .accessibilityIdentifier("\(accessibilityPrefix).markup.stroke")
            Button(AppStrings.ImageEditor.sampleColor, systemImage: "eyedropper") { viewModel.sampleStrokeColor() }
                .labelStyle(.iconOnly)
                .help(AppStrings.ImageEditor.sampleColor)
                .accessibilityIdentifier("\(accessibilityPrefix).markup.eyedropper")
            Toggle(AppStrings.ImageEditor.fillColor, isOn: Binding(
                get: { viewModel.markupStyle.fillColor != nil },
                set: { viewModel.setFillColor($0 ? (viewModel.markupStyle.fillColor ?? RasterColor(red: 1, green: 1, blue: 1, alpha: 0.85)) : nil) }
            ))
            .toggleStyle(.checkbox)
            .fixedSize()
            .accessibilityIdentifier("\(accessibilityPrefix).markup.fill-enabled")
            if let fill = viewModel.markupStyle.fillColor {
                ColorPicker(AppStrings.ImageEditor.fillColor, selection: Binding(
                    get: { Color(nsColor: fill.nsColor) },
                    set: { viewModel.setFillColor(RasterColor(NSColor($0))) }
                ), supportsOpacity: true)
                .labelsHidden()
                .accessibilityLabel(AppStrings.ImageEditor.fillColor)
                .accessibilityIdentifier("\(accessibilityPrefix).markup.fill")
            }
            Stepper(value: Binding(get: { Double(viewModel.markupStyle.lineWidth) }, set: { viewModel.setLineWidth($0) }),
                    in: 1...40, step: 1) {
                Text("\(AppStrings.ImageEditor.lineWidth) \(Int(viewModel.markupStyle.lineWidth))")
                    .monospacedDigit()
            }
            .fixedSize()
            .accessibilityIdentifier("\(accessibilityPrefix).markup.width")
            if viewModel.showsTextControls {
                textControls
            }
            Spacer(minLength: 8)
            if viewModel.hasSelectedMarkup {
                Button(AppStrings.ImageEditor.deleteItem, systemImage: "trash") { viewModel.deleteSelectedMarkup() }
                    .labelStyle(.iconOnly)
                    .help(AppStrings.ImageEditor.deleteItem)
                    .accessibilityIdentifier("\(accessibilityPrefix).markup.delete")
            }
        }
    }

    private var textControls: some View {
        HStack(spacing: 8) {
            TextField(AppStrings.ImageEditor.annotationTextPlaceholder, text: Binding(
                get: { viewModel.annotationText },
                set: { viewModel.setText($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 160)
            .focused($isTextFieldFocused)
            .accessibilityIdentifier("\(accessibilityPrefix).annotation.text")
            Picker(AppStrings.ImageEditor.annotationFont, selection: Binding(
                get: { viewModel.markupStyle.fontName },
                set: { viewModel.setFontName($0) }
            )) {
                ForEach(Self.fontFamilies, id: \.self) { family in
                    Text(family == "System" ? AppStrings.ImageEditor.annotationSystemFont : family).tag(family)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 150)
            .accessibilityLabel(AppStrings.ImageEditor.annotationFont)
            .accessibilityIdentifier("\(accessibilityPrefix).annotation.font")
            Stepper(value: Binding(get: { Double(viewModel.markupStyle.fontSize) }, set: { viewModel.setFontSize($0) }),
                    in: 8...144, step: 2) {
                Text(AppStrings.ImageEditor.annotationSize(Int(viewModel.markupStyle.fontSize)))
                    .monospacedDigit()
            }
            .fixedSize()
            .accessibilityIdentifier("\(accessibilityPrefix).annotation.size")
        }
    }
}

/// Adjust mode controls: color sliders with live preview, reset, and hold-to-compare.
@MainActor
struct RasterImageAdjustToolbar: View {
    @ObservedObject var viewModel: RasterImageEditorViewModel

    private struct SliderSpec: Identifiable {
        let id: String
        let title: String
        let keyPath: WritableKeyPath<RasterImageAdjustments, Double>
        let range: ClosedRange<Double>
    }

    private let sliders: [SliderSpec] = [
        SliderSpec(id: "exposure", title: AppStrings.ImageEditor.adjustExposure, keyPath: \.exposure, range: -2...2),
        SliderSpec(id: "contrast", title: AppStrings.ImageEditor.adjustContrast, keyPath: \.contrast, range: -1...1),
        SliderSpec(id: "saturation", title: AppStrings.ImageEditor.adjustSaturation, keyPath: \.saturation, range: -1...1),
        SliderSpec(id: "vibrance", title: AppStrings.ImageEditor.adjustVibrance, keyPath: \.vibrance, range: -1...1),
        SliderSpec(id: "temperature", title: AppStrings.ImageEditor.adjustTemperature, keyPath: \.temperature, range: -1...1),
        SliderSpec(id: "highlights", title: AppStrings.ImageEditor.adjustHighlights, keyPath: \.highlights, range: -1...1),
        SliderSpec(id: "shadows", title: AppStrings.ImageEditor.adjustShadows, keyPath: \.shadows, range: -1...1),
        SliderSpec(id: "sharpness", title: AppStrings.ImageEditor.adjustSharpness, keyPath: \.sharpness, range: 0...1)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], alignment: .leading, spacing: 4) {
                ForEach(sliders) { spec in
                    HStack(spacing: 6) {
                        Text(spec.title)
                            .frame(width: 82, alignment: .leading)
                        Slider(
                            value: Binding(get: { viewModel.adjustments[keyPath: spec.keyPath] },
                                           set: { viewModel.previewAdjustment(spec.keyPath, to: $0) }),
                            in: spec.range,
                            onEditingChanged: { editing in if !editing { viewModel.commitAdjustments() } }
                        )
                        .disabled(!viewModel.canAdjust)
                        .accessibilityLabel(spec.title)
                        .accessibilityValue(AppStrings.ImageEditor.adjustValue(viewModel.adjustments[keyPath: spec.keyPath]))
                        .accessibilityIdentifier("editor.preview.image.adjust.\(spec.id)")
                        Text(AppStrings.ImageEditor.adjustValue(viewModel.adjustments[keyPath: spec.keyPath]))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                    .font(AppTypographyTokens.imageStatus)
                }
            }
            HStack(spacing: 8) {
                Button(AppStrings.ImageEditor.adjustReset) { viewModel.resetAdjustments() }
                    .disabled(viewModel.adjustments.isIdentity || !viewModel.canAdjust)
                    .accessibilityIdentifier("editor.preview.image.adjust.reset")
                Text(AppStrings.ImageEditor.adjustCompare)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.5)))
                    .onLongPressGesture(minimumDuration: 0, maximumDistance: 50, pressing: { viewModel.setComparing($0) }, perform: {})
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { viewModel.setComparing(!viewModel.isComparing) }
                    .accessibilityIdentifier("editor.preview.image.adjust.compare")
            }
        }
    }
}
