import AppKit
import SwiftUI

enum RasterImageEditingMode: String, CaseIterable {
    case pan
    case crop
    case draw
    case annotate
}

enum RasterImagePreviewGeometry {
    static func centeredInsets(
        viewportSize: CGSize,
        imageSize: CGSize,
        magnification: CGFloat
    ) -> NSEdgeInsets {
        guard viewportSize.width > 0, viewportSize.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            return NSEdgeInsetsZero
        }

        let clampedMagnification = max(0, magnification)
        let scaledWidth = imageSize.width * clampedMagnification
        let scaledHeight = imageSize.height * clampedMagnification
        let horizontalInset = max(0, (viewportSize.width - scaledWidth) / 2.0)
        let verticalInset = max(0, (viewportSize.height - scaledHeight) / 2.0)

        return NSEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }
}

struct RasterImagePreviewHost: View {
    let fileURL: URL
    let onSaveDataRequest: ((URL, Data, @escaping (Result<Void, Error>) -> Void) -> Void)?
    let onDirtyStateChange: (Bool) -> Void

    @State private var editingMode: RasterImageEditingMode = .draw
    @State private var cropTrigger = 0
    @State private var clearTrigger = 0
    @State private var saveTrigger = 0
    @State private var actionStatus: String?
    @State private var hasPendingEdits = false
    @State private var annotationText = "Note"
    @State private var annotationFontFamily = "System"
    @State private var annotationFontSize = 14.0
    @Environment(\.appThemePalette) private var appThemePalette

    private static let annotationFontFamilies: [String] = {
        let families = NSFontManager.shared.availableFontFamilies.sorted()
        return ["System"] + families
    }()

    private var toolbarBackground: Color {
        appThemePalette.windowBackgroundColor.opacity(0.92)
    }

    private var modeHint: String {
        switch editingMode {
        case .pan:
            return "Pan: drag to move and pinch to zoom."
        case .crop:
            return "Crop: drag a selection, then click Apply Crop."
        case .draw:
            return "Draw: drag on the image to sketch."
        case .annotate:
            return "Annotate: click on the image to place a note."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    modeButton("Crop", mode: .crop, accessibilityIdentifier: "editor.preview.image.mode.crop")
                    modeButton("Draw", mode: .draw, accessibilityIdentifier: "editor.preview.image.mode.draw")
                    modeButton("Annotate", mode: .annotate, accessibilityIdentifier: "editor.preview.image.mode.annotate")
                    Divider()
                        .frame(height: 18)
                    Button("Apply Crop") {
                        cropTrigger += 1
                    }
                    .disabled(editingMode != .crop)
                    .accessibilityIdentifier("editor.preview.image.action.apply-crop")
                    Button("Save") {
                        saveTrigger += 1
                    }
                    .disabled(!hasPendingEdits)
                    .accessibilityIdentifier("editor.preview.image.action.save")
                    Button("Clear") {
                        clearTrigger += 1
                    }
                    .accessibilityIdentifier("editor.preview.image.action.clear")
                }
                .buttonStyle(.crispyvibesText)
                .controlSize(.small)

                Text(actionStatus ?? modeHint)
                    .font(AppTypographyTokens.imageStatus)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("editor.preview.image.status")

                if editingMode == .annotate {
                    HStack(spacing: 8) {
                        TextField("Annotation text", text: $annotationText)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 220)
                            .accessibilityIdentifier("editor.preview.image.annotation.text")
                        Picker("Font", selection: $annotationFontFamily) {
                            ForEach(Self.annotationFontFamilies, id: \.self) { family in
                                Text(family).tag(family)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 170)
                        .accessibilityIdentifier("editor.preview.image.annotation.font")
                        Stepper(value: $annotationFontSize, in: 8...72, step: 1) {
                            Text("Size \(Int(annotationFontSize))")
                        }
                        .frame(minWidth: 120)
                        .accessibilityIdentifier("editor.preview.image.annotation.size")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(toolbarBackground)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("editor.preview.image.toolbar")

            Divider()

            RasterImageFilePreview(
                fileURL: fileURL,
                editingMode: editingMode,
                cropToken: cropTrigger,
                clearToken: clearTrigger,
                saveToken: saveTrigger,
                annotationText: annotationText,
                annotationFontFamily: annotationFontFamily,
                annotationFontSize: annotationFontSize,
                onSaveDataRequest: onSaveDataRequest,
                onDirtyStateChange: { hasUnsavedEdits in
                    DispatchQueue.main.async {
                        hasPendingEdits = hasUnsavedEdits
                        onDirtyStateChange(hasUnsavedEdits)
                    }
                },
                onActionFeedback: { message in
                    DispatchQueue.main.async {
                        actionStatus = message
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func modeButton(
        _ title: String,
        mode: RasterImageEditingMode,
        accessibilityIdentifier: String
    ) -> some View {
        Button(title) {
            editingMode = mode
            actionStatus = nil
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
