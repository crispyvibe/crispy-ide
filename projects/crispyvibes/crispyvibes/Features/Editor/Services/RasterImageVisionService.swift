import CoreGraphics
import CoreImage
import Foundation
import Vision

/// A line of text found by OCR, positioned in the analyzed image.
struct RecognizedTextLine: Equatable, Identifiable, Sendable {
    let id = UUID()
    let text: String
    /// Normalized bounding box with a **top-left** origin (0…1 on both axes).
    let normalizedBox: CGRect
    let confidence: Float

    /// The box in a canvas of `size` (top-left origin).
    func box(in size: CGSize) -> CGRect {
        CGRect(x: normalizedBox.minX * size.width, y: normalizedBox.minY * size.height,
               width: normalizedBox.width * size.width, height: normalizedBox.height * size.height)
    }

    static func == (lhs: RecognizedTextLine, rhs: RecognizedTextLine) -> Bool {
        lhs.text == rhs.text && lhs.normalizedBox == rhs.normalizedBox && lhs.confidence == rhs.confidence
    }
}

/// An immutable alpha mask (white = keep) used by `.removeBackground`.
/// Equality is identity: each Vision result is a distinct edit.
final class RasterImageMask: Equatable, @unchecked Sendable {
    let image: CGImage

    init(image: CGImage) {
        self.image = image
    }

    static func == (lhs: RasterImageMask, rhs: RasterImageMask) -> Bool { lhs === rhs }
}

/// Errors from on-device image analysis.
enum RasterImageAnalysisError: LocalizedError, Equatable {
    case noTextFound
    case noSubjectFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noTextFound: return AppStrings.ImageEditor.statusNoTextFound
        case .noSubjectFound: return AppStrings.ImageEditor.statusNoSubjectFound
        case .failed(let reason): return reason
        }
    }
}

/// On-device Vision analysis (OCR, subject masks) on a background queue.
struct RasterImageVisionService: RasterImageAnalyzing {
    var queue = DispatchQueue(label: "com.crispyvibe.raster-image.vision", qos: .userInitiated)

    @discardableResult
    func recognizeText(in image: CGImage, completion: @escaping @MainActor (Result<[RecognizedTextLine], Error>) -> Void) -> RasterImageWorkHandle {
        let handle = RasterImageWorkHandle()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        handle.onCancel { request.cancel() }
        queue.async {
            guard !handle.isCancelled else { return }
            let result: Result<[RecognizedTextLine], Error> = Result {
                try VNImageRequestHandler(cgImage: image).perform([request])
                let lines = (request.results ?? []).compactMap { observation -> RecognizedTextLine? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let box = observation.boundingBox
                    return RecognizedTextLine(
                        text: candidate.string,
                        normalizedBox: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height),
                        confidence: candidate.confidence
                    )
                }
                guard !lines.isEmpty else { throw RasterImageAnalysisError.noTextFound }
                // Reading order: top to bottom, then left to right.
                return lines.sorted {
                    abs($0.normalizedBox.midY - $1.normalizedBox.midY) > 0.01
                        ? $0.normalizedBox.midY < $1.normalizedBox.midY
                        : $0.normalizedBox.minX < $1.normalizedBox.minX
                }
            }
            Self.deliver(result, handle: handle, completion: completion)
        }
        return handle
    }

    @discardableResult
    func foregroundMask(for image: CGImage, completion: @escaping @MainActor (Result<RasterImageMask, Error>) -> Void) -> RasterImageWorkHandle {
        let handle = RasterImageWorkHandle()
        let request = VNGenerateForegroundInstanceMaskRequest()
        handle.onCancel { request.cancel() }
        queue.async {
            guard !handle.isCancelled else { return }
            let result: Result<RasterImageMask, Error> = Result {
                let handler = VNImageRequestHandler(cgImage: image)
                try handler.perform([request])
                guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
                    throw RasterImageAnalysisError.noSubjectFound
                }
                let buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
                let ciMask = CIImage(cvPixelBuffer: buffer)
                guard let mask = CIContext().createCGImage(ciMask, from: ciMask.extent, format: .L8,
                                                           colorSpace: CGColorSpaceCreateDeviceGray()) else {
                    throw RasterImageAnalysisError.failed(AppStrings.ImageEditor.statusTransformFailed)
                }
                return RasterImageMask(image: mask)
            }
            Self.deliver(result, handle: handle, completion: completion)
        }
        return handle
    }

    private static func deliver<T>(_ result: Result<T, Error>, handle: RasterImageWorkHandle, completion: @escaping @MainActor (Result<T, Error>) -> Void) {
        DispatchQueue.main.async {
            guard !handle.isCancelled else { return }
            MainActor.assumeIsolated { completion(result) }
        }
    }
}
