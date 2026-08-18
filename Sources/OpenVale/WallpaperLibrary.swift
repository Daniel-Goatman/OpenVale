import AVFoundation
import Foundation

struct Wallpaper: Hashable, Identifiable {
    let url: URL
    let title: String
    let pixelWidth: Int
    let pixelHeight: Int

    var id: String { url.lastPathComponent }

    var resolutionLabel: String {
        guard pixelWidth > 0, pixelHeight > 0 else { return "Video" }
        let quality = pixelWidth >= 3_800 && pixelHeight >= 2_100 ? "4K · " : ""
        return "\(quality)\(pixelWidth)×\(pixelHeight)"
    }
}

struct WallpaperImportResult {
    let imported: [Wallpaper]
    let duplicateCount: Int
    let failures: [String]
}

final class WallpaperLibrary {
    static let supportedExtensions = ["mp4", "mov", "m4v"]

    let directoryURL: URL
    private let fileManager: FileManager

    init(
        directoryURL: URL = WallpaperLibrary.defaultDirectoryURL,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    static var defaultDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenVale", isDirectory: true)
            .appendingPathComponent("Wallpapers", isDirectory: true)
    }

    func prepare() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func wallpapers() async -> [Wallpaper] {
        guard
            let urls = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        var loadedWallpapers: [Wallpaper] = []
        for url in urls where Self.isSupportedVideo(url) {
            if let wallpaper = await Self.wallpaper(from: url) {
                loadedWallpapers.append(wallpaper)
            }
        }
        return loadedWallpapers.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    func importFiles(_ sourceURLs: [URL]) async -> WallpaperImportResult {
        do {
            try prepare()
        } catch {
            return WallpaperImportResult(
                imported: [],
                duplicateCount: 0,
                failures: ["Couldn’t create the OpenVale wallpaper folder: \(error.localizedDescription)"]
            )
        }

        var imported: [Wallpaper] = []
        var duplicateCount = 0
        var failures: [String] = []

        for sourceURL in sourceURLs {
            let didAccessSecurityScope = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccessSecurityScope {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                guard Self.isSupportedVideo(sourceURL) else {
                    throw ImportError.unsupportedType
                }
                guard await Self.wallpaper(from: sourceURL) != nil else {
                    throw ImportError.noVideoTrack
                }

                if let matchingURL = existingIdenticalFile(for: sourceURL) {
                    duplicateCount += 1
                    if let wallpaper = await Self.wallpaper(from: matchingURL) {
                        imported.append(wallpaper)
                    }
                    continue
                }

                let destinationURL = uniqueDestinationURL(for: sourceURL.lastPathComponent)
                let temporaryURL = directoryURL
                    .appendingPathComponent(".\(UUID().uuidString).importing")

                do {
                    try fileManager.copyItem(at: sourceURL, to: temporaryURL)
                    try fileManager.moveItem(at: temporaryURL, to: destinationURL)
                } catch {
                    try? fileManager.removeItem(at: temporaryURL)
                    throw error
                }

                guard let wallpaper = await Self.wallpaper(from: destinationURL) else {
                    try? fileManager.removeItem(at: destinationURL)
                    throw ImportError.noVideoTrack
                }
                imported.append(wallpaper)
            } catch {
                failures.append("\(sourceURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return WallpaperImportResult(
            imported: imported,
            duplicateCount: duplicateCount,
            failures: failures
        )
    }

    func moveToTrash(_ wallpaper: Wallpaper) throws {
        var resultingURL: NSURL?
        try fileManager.trashItem(at: wallpaper.url, resultingItemURL: &resultingURL)
    }

    private func existingIdenticalFile(for sourceURL: URL) -> URL? {
        let directMatch = directoryURL.appendingPathComponent(sourceURL.lastPathComponent)
        guard fileManager.fileExists(atPath: directMatch.path) else { return nil }
        return fileManager.contentsEqual(atPath: sourceURL.path, andPath: directMatch.path)
            ? directMatch
            : nil
    }

    private func uniqueDestinationURL(for filename: String) -> URL {
        let sourceURL = URL(fileURLWithPath: filename)
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        var candidate = directoryURL.appendingPathComponent(filename)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directoryURL
                .appendingPathComponent("\(base) \(suffix)")
                .appendingPathExtension(ext)
            suffix += 1
        }
        return candidate
    }

    static func displayTitle(for filename: String) -> String {
        let rawBase = URL(fileURLWithPath: filename)
            .deletingPathExtension()
            .lastPathComponent
        let base = rawBase.replacingOccurrences(
            of: #"[._ -]\d{3,4}x\d{3,4}$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return base
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map { word in
                word.allSatisfy(\.isUppercase) ? String(word) : word.capitalized
            }
            .joined(separator: " ")
    }

    static func wallpaper(from url: URL) async -> Wallpaper? {
        let asset = AVURLAsset(url: url)
        do {
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                return nil
            }
            async let naturalSize = videoTrack.load(.naturalSize)
            async let preferredTransform = videoTrack.load(.preferredTransform)
            let transformedSize = try await naturalSize.applying(preferredTransform)
            let width = Int(abs(transformedSize.width).rounded())
            let height = Int(abs(transformedSize.height).rounded())

            return Wallpaper(
                url: url,
                title: displayTitle(for: url.lastPathComponent),
                pixelWidth: width,
                pixelHeight: height
            )
        } catch {
            return nil
        }
    }

    static func isSupportedVideo(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}

private enum ImportError: LocalizedError {
    case unsupportedType
    case noVideoTrack

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            return "OpenVale supports MP4, MOV, and M4V video files."
        case .noVideoTrack:
            return "The file does not contain a playable video track."
        }
    }
}
