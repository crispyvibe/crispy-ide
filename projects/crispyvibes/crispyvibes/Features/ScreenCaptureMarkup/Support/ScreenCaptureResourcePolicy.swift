import Foundation

/// Overflow-safe allocation policy required by F062 (64 MP and 512 MiB).
struct ScreenCaptureResourcePolicy: Sendable {
    static let maximumPixelCount: UInt64 = 64_000_000
    static let maximumWorkingBytes: UInt64 = 512 * 1_024 * 1_024

    let maximumPixelCount: UInt64
    let maximumWorkingBytes: UInt64

    init(
        maximumPixelCount: UInt64 = Self.maximumPixelCount,
        maximumWorkingBytes: UInt64 = Self.maximumWorkingBytes
    ) {
        self.maximumPixelCount = maximumPixelCount
        self.maximumWorkingBytes = maximumWorkingBytes
    }

    /// Validates dimensions before allocation and returns the conservative estimated working set.
    @discardableResult
    func validate(
        pixelWidth: Int,
        pixelHeight: Int,
        bytesPerPixel: UInt64 = 4,
        simultaneousBuffers: UInt64 = 2,
        additionalBytes: UInt64 = 0
    ) throws -> UInt64 {
        guard pixelWidth > 0, pixelHeight > 0 else { throw ScreenCaptureError.invalidGeometry }

        let width = UInt64(pixelWidth)
        let height = UInt64(pixelHeight)
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        guard !pixelOverflow else {
            throw ScreenCaptureError.resourceLimitExceeded(pixelCount: .max, estimatedBytes: .max)
        }

        let (bytesPerBuffer, byteOverflow) = pixelCount.multipliedReportingOverflow(by: bytesPerPixel)
        let (bufferBytes, bufferOverflow) = bytesPerBuffer.multipliedReportingOverflow(by: simultaneousBuffers)
        let (estimatedBytes, additionOverflow) = bufferBytes.addingReportingOverflow(additionalBytes)
        guard !byteOverflow, !bufferOverflow, !additionOverflow,
              pixelCount <= maximumPixelCount,
              estimatedBytes <= maximumWorkingBytes else {
            throw ScreenCaptureError.resourceLimitExceeded(
                pixelCount: pixelCount,
                estimatedBytes: byteOverflow || bufferOverflow || additionOverflow ? .max : estimatedBytes
            )
        }
        return estimatedBytes
    }
}
