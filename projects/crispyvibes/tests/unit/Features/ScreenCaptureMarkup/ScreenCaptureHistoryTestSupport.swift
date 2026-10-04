import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import CrispyVibes

final class ScreenCaptureHistoryTestClock: ScreenCaptureHistoryClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(_ interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }
}

enum ScreenCaptureHistoryTestFixture {
    static func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("screen-history-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func png(
        width: Int = 24,
        height: Int = 12,
        metadataValue: String? = nil
    ) throws -> Data {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw ScreenCaptureHistoryError.encodingFailed
        }
        context.setFillColor(red: 0.15, green: 0.45, blue: 0.75, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw ScreenCaptureHistoryError.encodingFailed }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenCaptureHistoryError.encodingFailed
        }
        var properties: [CFString: Any] = [:]
        if let metadataValue {
            properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGDescription: metadataValue]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenCaptureHistoryError.encodingFailed
        }
        return output as Data
    }

    static func content(_ data: Data, width: Double = 24, height: Double = 12) -> ScreenCaptureHistoryContent {
        ScreenCaptureHistoryContent(pngData: data, canvasWidth: width, canvasHeight: height, exportScale: 1)
    }
}

actor ScreenCaptureHistoryFastProcessor: ScreenCaptureHistoryImageProcessing {
    private let image: ScreenCaptureHistoryImage

    init(image: ScreenCaptureHistoryImage) { self.image = image }

    func prepare(pngData: Data, maximumThumbnailPixelSize: Int) async throws -> ScreenCaptureHistoryPreparedImages {
        guard !pngData.isEmpty, maximumThumbnailPixelSize > 0 else {
            throw ScreenCaptureHistoryError.invalidContent
        }
        return ScreenCaptureHistoryPreparedImages(
            canonicalPNG: pngData,
            thumbnailPNG: pngData,
            pixelWidth: image.pixelWidth,
            pixelHeight: image.pixelHeight
        )
    }

    func decodePNG(_ data: Data) async throws -> ScreenCaptureHistoryImage {
        guard !data.isEmpty else { throw ScreenCaptureHistoryError.decodingFailed }
        return image
    }
}

actor ScreenCaptureHistoryBlockingProcessor: ScreenCaptureHistoryImageProcessing {
    private enum Operation { case prepare, decode }

    private let base = ScreenCaptureThumbnailService()
    private var blockedOperation: Operation?
    private var started = false
    private var cancellationObservationCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func setBlocking(_ value: Bool) {
        blockedOperation = value ? .prepare : nil
        started = false
        cancellationObservationCount = 0
    }

    func setBlockingDecode() {
        blockedOperation = .decode
        started = false
        cancellationObservationCount = 0
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func waitUntilCancellationObserved() async {
        while cancellationObservationCount == 0 { await Task.yield() }
    }

    func release() {
        continuation?.resume()
        continuation = nil
        blockedOperation = nil
    }

    func prepare(pngData: Data, maximumThumbnailPixelSize: Int) async throws -> ScreenCaptureHistoryPreparedImages {
        let result = try await base.prepare(
            pngData: pngData,
            maximumThumbnailPixelSize: maximumThumbnailPixelSize
        )
        try await blockIfNeeded(.prepare)
        return result
    }

    func decodePNG(_ data: Data) async throws -> ScreenCaptureHistoryImage {
        let result = try await base.decodePNG(data)
        try await blockIfNeeded(.decode)
        return result
    }

    private func blockIfNeeded(_ operation: Operation) async throws {
        guard blockedOperation == operation else { return }
        started = true
        await withCheckedContinuation { continuation = $0 }
        do {
            try Task.checkCancellation()
        } catch {
            cancellationObservationCount += 1
            throw error
        }
    }
}


enum ScreenCaptureHistoryPostCommitGate: Sendable {
    case loadEntries
    case thumbnail
}

/// Repository test decorator that blocks only after an add/update has committed downstream.
actor ScreenCaptureHistoryPostCommitGateRepository: ScreenCaptureHistoryRepository {
    private let base: any ScreenCaptureHistoryRepository
    private var armedGate: ScreenCaptureHistoryPostCommitGate?
    private var hasCommittedMutation = false
    private var isBlocked = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(base: any ScreenCaptureHistoryRepository) {
        self.base = base
    }

    func arm(_ gate: ScreenCaptureHistoryPostCommitGate) {
        armedGate = gate
        hasCommittedMutation = false
        isBlocked = false
    }

    func waitUntilBlocked() async {
        while !isBlocked { await Task.yield() }
    }

    func release() {
        continuation?.resume()
        continuation = nil
        armedGate = nil
        isBlocked = false
    }

    func loadEntries() async throws -> [ScreenCaptureHistoryEntry] {
        if hasCommittedMutation, armedGate == .loadEntries {
            try await block()
        }
        return try await base.loadEntries()
    }

    func add(
        id: UUID,
        content: ScreenCaptureHistoryContent
    ) async throws -> ScreenCaptureHistoryEntry {
        let entry = try await base.add(id: id, content: content)
        hasCommittedMutation = true
        return entry
    }

    func update(
        id: UUID,
        content: ScreenCaptureHistoryContent
    ) async throws -> ScreenCaptureHistoryEntry {
        let entry = try await base.update(id: id, content: content)
        hasCommittedMutation = true
        return entry
    }

    func thumbnail(for id: UUID) async throws -> ScreenCaptureHistoryImage {
        if hasCommittedMutation, armedGate == .thumbnail {
            try await block()
        }
        return try await base.thumbnail(for: id)
    }

    func flattenedSource(for id: UUID) async throws -> ScreenCaptureHistoryImage {
        try await base.flattenedSource(for: id)
    }

    func delete(id: UUID) async throws {
        try await base.delete(id: id)
    }

    func clear() async throws {
        try await base.clear()
    }

    private func block() async throws {
        isBlocked = true
        await withCheckedContinuation { continuation = $0 }
        try Task.checkCancellation()
    }
}

final class ScreenCaptureHistoryWarningRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ScreenCaptureHistoryMaintenanceWarning] = []

    var warnings: [ScreenCaptureHistoryMaintenanceWarning] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ warning: ScreenCaptureHistoryMaintenanceWarning) {
        lock.lock()
        storage.append(warning)
        lock.unlock()
    }
}
