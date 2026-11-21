import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Owns the attachment directory and all image/file IO. Methods are synchronous
/// and safe to call off the main thread; callers use `Task.detached` for large files.
struct AttachmentStore: Sendable {
    static let shared = AttachmentStore()

    let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.root = base.appendingPathComponent("Attachments", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func url(for fileName: String) -> URL {
        root.appendingPathComponent(fileName)
    }

    func exists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: fileName).path)
    }

    func byteCount(for fileName: String) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url(for: fileName).path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }

    func totalBytes() -> Int {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.reduce(0) { partial, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return partial + size
        }
    }

    // MARK: - Writing

    /// Downsamples before writing so a 48 MP photo never lands on disk at full size.
    func saveImageData(_ data: Data, maxPixel: CGFloat = 2048, quality: CGFloat = 0.86) throws -> String {
        let fileName = "img-\(UUID().uuidString).jpg"
        let destination = url(for: fileName)
        guard let image = Self.downsample(data: data, to: maxPixel),
              let encoded = image.jpegData(compressionQuality: quality) else {
            // Fall back to the original bytes rather than losing the attachment.
            try data.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
            return fileName
        }
        try encoded.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
        return fileName
    }

    func saveDocument(from source: URL) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.isEmpty ? "dat" : source.pathExtension
        let fileName = "file-\(UUID().uuidString).\(ext)"
        let destination = url(for: fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return fileName
    }

    func saveAudio(from temporaryURL: URL) throws -> String {
        let fileName = "audio-\(UUID().uuidString).m4a"
        let destination = url(for: fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return fileName
    }

    func delete(fileNames: [String]) {
        for name in fileNames {
            try? FileManager.default.removeItem(at: url(for: name))
        }
    }

    // MARK: - Reading

    func image(for fileName: String, maxPixel: CGFloat = 1600) -> UIImage? {
        guard let data = try? Data(contentsOf: url(for: fileName)) else { return nil }
        return Self.downsample(data: data, to: maxPixel)
    }

    /// Uses ImageIO thumbnailing so scrolling a note never decodes full resolution images.
    static func downsample(data: Data, to maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// Small in-memory image cache so a grid of thumbnails does not re-decode on every
/// list update. Bounded by count to keep memory flat on large notes.
@MainActor
@Observable
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var images: [String: UIImage] = [:]
    private var order: [String] = []
    private let limit = 120

    func image(named fileName: String, maxPixel: CGFloat = 400) -> UIImage? {
        let key = "\(fileName)#\(Int(maxPixel))"
        if let cached = images[key] {
            return cached
        }
        guard let image = AttachmentStore.shared.image(for: fileName, maxPixel: maxPixel) else {
            return nil
        }
        images[key] = image
        order.append(key)
        if order.count > limit {
            let evicted = order.removeFirst()
            images.removeValue(forKey: evicted)
        }
        return image
    }

    func clear() {
        images.removeAll()
        order.removeAll()
    }
}
