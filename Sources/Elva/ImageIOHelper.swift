import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageFormat: String, CaseIterable {
    case png, jpg

    var utType: UTType { self == .png ? .png : .jpeg }
    var fileExtension: String { rawValue }
    var title: String { self == .png ? "PNG" : "JPG" }
}

enum ImageIOHelper {
    static func data(for image: CGImage, format: ImageFormat) -> Data? {
        // JPG saydamlık desteklemez; lasso kesimleri siyah çıkmasın diye beyaz zemine bas.
        let source = format == .jpg ? flattenedOnWhite(image) : image
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            return nil
        }
        let props: [CFString: Any] = format == .jpg ? [kCGImageDestinationLossyCompressionQuality: 0.92] : [:]
        CGImageDestinationAddImage(dest, source, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    static func write(_ image: CGImage, to url: URL, format: ImageFormat) throws {
        guard let data = data(for: image, format: format) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }

    static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func thumbnail(_ url: URL, maxPixelSize: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func flattenedOnWhite(_ image: CGImage) -> CGImage {
        AnnotationRenderer.render(base: image, annotations: [], background: .white)
    }

    @MainActor
    static func copyToPasteboard(_ image: CGImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        pb.writeObjects([nsImage])
        if let png = data(for: image, format: .png) {
            pb.setData(png, forType: .png)
        }
    }

    static func fileBaseName(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Ekran Görüntüsü \(f.string(from: date))"
    }
}
