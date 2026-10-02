import Foundation

extension RasterImageEditingMode {
    /// Toolbar title.
    var title: String {
        switch self {
        case .pan: return AppStrings.ImageEditor.modePan
        case .crop: return AppStrings.ImageEditor.modeCrop
        case .markup: return AppStrings.ImageEditor.modeMarkup
        case .adjust: return AppStrings.ImageEditor.modeAdjust
        }
    }

    /// Status-line hint for the mode.
    var hint: String {
        switch self {
        case .pan: return AppStrings.ImageEditor.hintPan
        case .crop: return AppStrings.ImageEditor.hintCrop
        case .markup: return AppStrings.ImageEditor.hintMarkup
        case .adjust: return AppStrings.ImageEditor.hintAdjust
        }
    }
}

extension RasterMarkupTool {
    var title: String {
        switch self {
        case .select: return AppStrings.ImageEditor.toolSelect
        case .pen: return AppStrings.ImageEditor.toolPen
        case .line: return AppStrings.ImageEditor.toolLine
        case .arrow: return AppStrings.ImageEditor.toolArrow
        case .rectangle: return AppStrings.ImageEditor.toolRectangle
        case .ellipse: return AppStrings.ImageEditor.toolEllipse
        case .highlight: return AppStrings.ImageEditor.toolHighlight
        case .text: return AppStrings.ImageEditor.toolText
        case .blur: return AppStrings.ImageEditor.toolBlur
        case .pixelate: return AppStrings.ImageEditor.toolPixelate
        case .redact: return AppStrings.ImageEditor.toolRedact
        }
    }

    var systemImage: String {
        switch self {
        case .select: return "cursorarrow"
        case .pen: return "scribble"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .blur: return "drop"
        case .pixelate: return "square.grid.3x3"
        case .redact: return "rectangle.fill"
        }
    }

    var hint: String {
        switch self {
        case .select: return AppStrings.ImageEditor.hintSelect
        case .text: return AppStrings.ImageEditor.hintText
        case .blur, .pixelate: return AppStrings.ImageEditor.hintObscure
        case .redact: return AppStrings.ImageEditor.hintRedact
        default: return AppStrings.ImageEditor.hintShape
        }
    }
}

extension RasterMarkupItem.Kind {
    /// Spoken name for VoiceOver.
    var accessibilityName: String {
        switch self {
        case .pen: return AppStrings.ImageEditor.toolPen
        case .line: return AppStrings.ImageEditor.toolLine
        case .arrow: return AppStrings.ImageEditor.toolArrow
        case .rectangle: return AppStrings.ImageEditor.toolRectangle
        case .ellipse: return AppStrings.ImageEditor.toolEllipse
        case .highlight: return AppStrings.ImageEditor.toolHighlight
        case .text(let text, _): return AppStrings.ImageEditor.accessibilityTextItem(text)
        case .blur: return AppStrings.ImageEditor.toolBlur
        case .pixelate: return AppStrings.ImageEditor.toolPixelate
        case .redact: return AppStrings.ImageEditor.toolRedact
        }
    }
}
