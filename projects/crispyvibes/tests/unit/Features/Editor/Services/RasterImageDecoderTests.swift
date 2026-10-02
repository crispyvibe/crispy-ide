import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CrispyVibes

/// F009 Phase 0: every decode branch yields the same upright pixels; exports write orientation 1;
/// lossy-overwrite sources are detected.
final class RasterImageDecoderTests: XCTestCase {
    private var tempRoot: URL!
    private let decoder = RasterImageDecoder()
    private let fixtures = RasterImageTestFixtures.self

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("RasterImageDecoderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func samplePoints(for image: CGImage) -> [(Int, Int)] {
        let w = image.width, h = image.height
        return [(w / 4, h / 4), (3 * w / 4, h / 4), (w / 4, 3 * h / 4), (3 * w / 4, 3 * h / 4)]
    }

    private func assertBranchesAgree(type: UTType, ext: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let raw = fixtures.quadrantImage(width: 64, height: 32)
        for orientation in UInt32(1)...8 {
            let url = tempRoot.appendingPathComponent("o\(orientation).\(ext)")
            guard fixtures.write([raw], type: type, to: url, orientation: orientation) else {
                throw XCTSkip("\(ext) encoding unavailable")
            }
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let info = try XCTUnwrap(decoder.sourceInfo(for: source))
            let swaps = orientation >= 5
            XCTAssertEqual(info.pixelWidth, swaps ? 32 : 64, "orientation \(orientation)", file: file, line: line)
            XCTAssertEqual(info.pixelHeight, swaps ? 64 : 32, "orientation \(orientation)", file: file, line: line)

            let full = try XCTUnwrap(decoder.fullResolutionImage(from: source, info: info))
            let proxy = try XCTUnwrap(decoder.proxyImage(from: source, maxPixelSize: 64))
            XCTAssertEqual(full.width, proxy.width, "orientation \(orientation)", file: file, line: line)
            XCTAssertEqual(full.height, proxy.height, "orientation \(orientation)", file: file, line: line)
            for (x, y) in samplePoints(for: full) {
                let a = fixtures.pixel(full, x: x, y: y)
                let b = fixtures.pixel(proxy, x: x, y: y)
                XCTAssertTrue(fixtures.matches(a, b), "orientation \(orientation) at (\(x),\(y)): full \(a) proxy \(b)", file: file, line: line)
            }
        }
    }

    func test_jpegOrientations1Through8_fullResolutionMatchesImageIOTransform() throws {
        try assertBranchesAgree(type: .jpeg, ext: "jpg")
    }

    func test_heicOrientations1Through8_fullResolutionMatchesImageIOTransform() throws {
        try assertBranchesAgree(type: .heic, ext: "heic")
    }

    func test_orientation6_rawTopLeftAppearsTopRight() throws {
        let url = tempRoot.appendingPathComponent("right.jpg")
        XCTAssertTrue(fixtures.write([fixtures.quadrantImage(width: 64, height: 32)], type: .jpeg, to: url, orientation: 6))
        let result = try XCTUnwrap(decoder.decode(contentsOf: url, maxPixelSize: 1024))
        XCTAssertTrue(result.isFullResolution)
        XCTAssertEqual(result.image.width, 32)
        XCTAssertEqual(result.image.height, 64)
        // Raw top-left quadrant (red) is displayed at the top-right after a 90° clockwise turn.
        XCTAssertTrue(fixtures.matches(fixtures.pixel(result.image, x: 24, y: 16), fixtures.quadrantColors[0]))
    }

    func test_proxyBranch_isUprightAndFlaggedAsReducedResolution() throws {
        let url = tempRoot.appendingPathComponent("big.jpg")
        XCTAssertTrue(fixtures.write([fixtures.quadrantImage(width: 200, height: 100)], type: .jpeg, to: url, orientation: 6))
        var smallLimitDecoder = RasterImageDecoder()
        smallLimitDecoder.fullResolutionEdgeLimit = 16
        let result = try XCTUnwrap(smallLimitDecoder.decode(contentsOf: url, maxPixelSize: 50))
        XCTAssertFalse(result.isFullResolution)
        XCTAssertEqual(result.sourceInfo.pixelWidth, 100)
        XCTAssertEqual(result.sourceInfo.pixelHeight, 200)
        XCTAssertLessThan(result.image.height, 200)
        XCTAssertGreaterThan(result.image.height, result.image.width, "proxy must be upright (portrait)")
        XCTAssertEqual(
            RasterImageSavePolicy.blockReason(for: result.sourceInfo, baselinePixelWidth: result.image.width, baselinePixelHeight: result.image.height),
            .reducedResolution(sourceWidth: 100, sourceHeight: 200, workingWidth: result.image.width, workingHeight: result.image.height)
        )
    }

    func test_sourceBelow4096ButAboveProxyRequest_decodesFullResolutionAndStaysSaveable() throws {
        let url = tempRoot.appendingPathComponent("mid.png")
        XCTAssertTrue(fixtures.write([fixtures.quadrantImage(width: 3000, height: 40)], type: .png, to: url))
        let result = try XCTUnwrap(decoder.decode(contentsOf: url, maxPixelSize: 1024))
        XCTAssertTrue(result.isFullResolution)
        XCTAssertEqual(result.image.width, 3000)
        XCTAssertNil(RasterImageSavePolicy.blockReason(for: result.sourceInfo, baselinePixelWidth: 3000, baselinePixelHeight: 40))
    }

    func test_multiFrameGIFAndTIFF_areDetected() throws {
        let frame = fixtures.quadrantImage(width: 16, height: 16)
        for (type, ext) in [(UTType.gif, "gif"), (UTType.tiff, "tiff")] {
            let url = tempRoot.appendingPathComponent("multi.\(ext)")
            XCTAssertTrue(fixtures.write([frame, frame], type: type, to: url))
            let result = try XCTUnwrap(decoder.decode(contentsOf: url, maxPixelSize: 1024))
            XCTAssertEqual(result.sourceInfo.frameCount, 2, ext)
            XCTAssertEqual(
                RasterImageSavePolicy.blockReason(for: result.sourceInfo, baselinePixelWidth: 16, baselinePixelHeight: 16),
                .multipleFrames(count: 2),
                ext
            )
        }
    }

    func test_sixteenBitPNG_isDetected() throws {
        let url = tempRoot.appendingPathComponent("deep.png")
        XCTAssertTrue(fixtures.write([fixtures.sixteenBitImage(width: 8, height: 8)], type: .png, to: url))
        let result = try XCTUnwrap(decoder.decode(contentsOf: url, maxPixelSize: 1024))
        XCTAssertEqual(result.sourceInfo.bitDepth, 16)
        XCTAssertEqual(
            RasterImageSavePolicy.blockReason(for: result.sourceInfo, baselinePixelWidth: 8, baselinePixelHeight: 8),
            .highBitDepth(bitsPerComponent: 16)
        )
    }

    func test_singleFrame8BitFullResolution_isSaveable() {
        let info = RasterImageSourceInfo(pixelWidth: 10, pixelHeight: 10, exifOrientation: 1, frameCount: 1, bitDepth: 8, hasGainMap: false)
        XCTAssertNil(RasterImageSavePolicy.blockReason(for: info, baselinePixelWidth: 10, baselinePixelHeight: 10))
        let hdr = RasterImageSourceInfo(pixelWidth: 10, pixelHeight: 10, exifOrientation: 1, frameCount: 1, bitDepth: 8, hasGainMap: true)
        XCTAssertEqual(RasterImageSavePolicy.blockReason(for: hdr, baselinePixelWidth: 10, baselinePixelHeight: 10), .hdrGainMap)
    }

    func test_export_writesOrientation1AndUprightPixels() throws {
        let sourceURL = tempRoot.appendingPathComponent("rotated.jpg")
        XCTAssertTrue(fixtures.write([fixtures.quadrantImage(width: 64, height: 32)], type: .jpeg, to: sourceURL, orientation: 6))
        let decoded = try XCTUnwrap(decoder.decode(contentsOf: sourceURL, maxPixelSize: 1024))

        let outputURL = tempRoot.appendingPathComponent("out.jpg")
        let data = try RasterImagePersistence.encodedData(for: fixtures.nsImage(decoded.image), destinationURL: outputURL)
        try data.write(to: outputURL)

        let outSource = try XCTUnwrap(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(outSource, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyOrientation] as? UInt32 ?? 1, 1)
        let reopened = try XCTUnwrap(decoder.decode(contentsOf: outputURL, maxPixelSize: 1024))
        XCTAssertEqual(reopened.image.width, 32)
        XCTAssertEqual(reopened.image.height, 64)
        XCTAssertTrue(fixtures.matches(fixtures.pixel(reopened.image, x: 24, y: 16), fixtures.quadrantColors[0]))
    }
}
