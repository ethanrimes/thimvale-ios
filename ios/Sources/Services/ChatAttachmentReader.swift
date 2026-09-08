import Foundation
import PDFKit
import ImageIO
import UIKit
import CryptoKit

actor ChatAttachmentReader {
    static let maximumFileBytes = 25_000_000
    static let textExtensions: Set<String> = ["txt", "md", "markdown", "csv", "json", "html", "htm", "rst", "log", "yaml", "yml", "xml", "swift", "py", "js", "ts", "kt", "java", "c", "h", "cpp"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "bmp", "tif", "tiff"]

    func read(_ url: URL) throws -> ChatAttachment {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isDirectory != true else {
            throw PocketError.message("Choose individual files, not folders or symbolic links.")
        }
        var result: Result<ChatAttachment, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readable in
            result = Result {
                try Task.checkCancellation()
                let size = try readable.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= Self.maximumFileBytes else { throw PocketError.message("Each attachment must be 25 MB or smaller.") }
                let handle = try FileHandle(forReadingFrom: readable)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: Self.maximumFileBytes + 1) ?? Data()
                guard data.count <= Self.maximumFileBytes else { throw PocketError.message("Each attachment must be 25 MB or smaller.") }
                return try Self.decode(data, name: url.lastPathComponent)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw PocketError.message("This file could not be opened. Download it in Files, then try again.") }
        try Task.checkCancellation()
        return try result.get()
    }

    static func decode(_ data: Data, name: String) throws -> ChatAttachment {
        try Task.checkCancellation()
        guard data.count <= maximumFileBytes else { throw PocketError.message("Each attachment must be 25 MB or smaller.") }
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if imageExtensions.contains(ext) {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, Double(width) * Double(height) <= 100_000_000 else {
                throw PocketError.message("This image is unreadable or exceeds 100 megapixels.")
            }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceShouldCacheImmediately: true]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.82), jpeg.count <= 1_500_000 else {
                throw PocketError.message("This image could not be prepared. Try a smaller JPEG or PNG.")
            }
            return .init(name: name, originalBytes: Int64(data.count), fingerprint: fingerprint, imageData: jpeg)
        }
        var sections: [ChatAttachment.Section] = []
        if ext == "pdf" {
            guard let pdf = PDFDocument(data: data), !pdf.isLocked, pdf.pageCount <= 200 else {
                throw PocketError.message("Choose an unlocked PDF with at most 200 pages.")
            }
            var bytes = 0
            for index in 0..<pdf.pageCount {
                try Task.checkCancellation()
                let text = pdf.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                bytes += text.utf8.count
                guard bytes <= ChatAttachment.maximumTextBytes else { throw PocketError.message("This PDF contains too much text for a chat attachment. Import it into Knowledge instead.") }
                if !text.isEmpty { sections.append(.init(text: text, page: index + 1)) }
            }
        } else {
            guard textExtensions.contains(ext) else { throw PocketError.message("Use text, Markdown, CSV, JSON, HTML, a PDF with selectable text, or an image. This file type is not supported.") }
            guard var text = String(data: data, encoding: .utf8), !text.contains("\0") else { throw PocketError.message("This file is not readable UTF-8 text.") }
            if ext == "html" || ext == "htm" { text = try KnowledgeService.plainText(text) }
            guard text.utf8.count <= ChatAttachment.maximumTextBytes else { throw PocketError.message("This file contains too much text for a chat attachment. Import it into Knowledge instead.") }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { sections = [.init(text: text)] }
        }
        guard !sections.isEmpty else { throw PocketError.message("No readable text was found. Scanned PDFs need selectable text; you can attach an image to a vision model instead.") }
        return .init(name: name, originalBytes: Int64(data.count), fingerprint: fingerprint, sections: sections)
    }
}
