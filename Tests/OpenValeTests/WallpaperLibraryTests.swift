import AVFoundation
import CoreVideo
import Foundation
import XCTest
@testable import OpenVale

final class WallpaperLibraryTests: XCTestCase {
    func testDisplayTitleUsesReadableWords() {
        XCTAssertEqual(
            WallpaperLibrary.displayTitle(for: "spring-meadow.3840x2160.mp4"),
            "Spring Meadow"
        )
        XCTAssertEqual(
            WallpaperLibrary.displayTitle(for: "misty_forest.MOV"),
            "Misty Forest"
        )
    }

    func testSupportedVideoExtensionsAreCaseInsensitive() {
        XCTAssertTrue(WallpaperLibrary.isSupportedVideo(URL(fileURLWithPath: "/tmp/view.MP4")))
        XCTAssertTrue(WallpaperLibrary.isSupportedVideo(URL(fileURLWithPath: "/tmp/view.mov")))
        XCTAssertTrue(WallpaperLibrary.isSupportedVideo(URL(fileURLWithPath: "/tmp/view.m4v")))
        XCTAssertFalse(WallpaperLibrary.isSupportedVideo(URL(fileURLWithPath: "/tmp/view.gif")))
    }

    func testResolutionLabelDoesNotClaimFourKForHD() {
        let fourK = Wallpaper(
            url: URL(fileURLWithPath: "/tmp/4k.mp4"),
            title: "4K",
            pixelWidth: 3840,
            pixelHeight: 2160
        )
        let hd = Wallpaper(
            url: URL(fileURLWithPath: "/tmp/hd.mp4"),
            title: "HD",
            pixelWidth: 1920,
            pixelHeight: 1080
        )

        XCTAssertEqual(fourK.resolutionLabel, "4K · 3840×2160")
        XCTAssertEqual(hd.resolutionLabel, "1920×1080")
    }

    func testImportCopiesBytesWithoutReencodingAndSkipsDuplicate() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        let libraryDirectory = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = sourceDirectory.appendingPathComponent("tiny-meadow.mov")
        try await makeTestMovie(at: sourceURL)
        let sourceData = try Data(contentsOf: sourceURL)
        let library = WallpaperLibrary(directoryURL: libraryDirectory)

        let firstImport = await library.importFiles([sourceURL])
        XCTAssertEqual(firstImport.failures, [])
        XCTAssertEqual(firstImport.duplicateCount, 0)
        XCTAssertEqual(firstImport.imported.count, 1)
        let copiedURL = try XCTUnwrap(firstImport.imported.first?.url)
        XCTAssertEqual(try Data(contentsOf: copiedURL), sourceData)

        let secondImport = await library.importFiles([sourceURL])
        XCTAssertEqual(secondImport.failures, [])
        XCTAssertEqual(secondImport.duplicateCount, 1)
        let wallpapersAfterDuplicate = await library.wallpapers()
        XCTAssertEqual(wallpapersAfterDuplicate.count, 1)
    }

    func testInvalidMovieIsRejectedWithoutLeavingAFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        let libraryDirectory = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let invalidURL = sourceDirectory.appendingPathComponent("not-a-video.mp4")
        try Data("not video data".utf8).write(to: invalidURL)
        let library = WallpaperLibrary(directoryURL: libraryDirectory)

        let result = await library.importFiles([invalidURL])
        XCTAssertEqual(result.imported.count, 0)
        XCTAssertEqual(result.failures.count, 1)
        let wallpapersAfterFailure = await library.wallpapers()
        XCTAssertEqual(wallpapersAfterFailure.count, 0)
    }

    private func makeTestMovie(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 16,
                AVVideoHeightKey: 16
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 16,
                kCVPixelBufferHeightKey as String: 16
            ]
        )
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let pool = try XCTUnwrap(adaptor.pixelBufferPool)
        var optionalBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer), kCVReturnSuccess)
        let buffer = try XCTUnwrap(optionalBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            memset(baseAddress, 0x40, CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        while !input.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(adaptor.append(buffer, withPresentationTime: .zero))
        input.markAsFinished()

        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        if writer.status != .completed {
            throw try XCTUnwrap(writer.error)
        }
    }
}
