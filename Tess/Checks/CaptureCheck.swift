import AppKit
import ImageIO
import UniformTypeIdentifiers

@main @MainActor struct CaptureCheck {
    static func png(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func assertUnchanged(_ url: URL, _ expected: Data) throws {
        let current = try Data(contentsOf: url)
        precondition(current == expected, "Rejected replacement must leave the original bytes unchanged")
    }

    static func main() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("Tess-capture-check-\(UUID().uuidString)", isDirectory: true)
        let captures = directory.appendingPathComponent("Captures", isDirectory: true)
        try manager.createDirectory(at: captures, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let service = CaptureService(capturesDirectory: captures)
        let imageURL = captures.appendingPathComponent(UUID().uuidString + ".png")
        let original = png(width: 4, height: 3, red: 1, green: 0, blue: 0)
        let replacement = png(width: 4, height: 3, red: 0, green: 1, blue: 0)
        precondition(original != replacement)
        try original.write(to: imageURL)

        precondition(service.replaceImage(at: imageURL, pngData: replacement))
        precondition(service.lastError == nil)
        try assertUnchanged(imageURL, replacement)
        let reopened = CGImageSourceCreateWithURL(imageURL as CFURL, nil)!
        precondition(CGImageSourceGetType(reopened) as String? == UTType.png.identifier)
        let image = CGImageSourceCreateImageAtIndex(reopened, 0, nil)!
        precondition(image.width == 4 && image.height == 3)
        let decoded = CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 16,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        decoded.draw(image, in: CGRect(x: 0, y: 0, width: 4, height: 3))
        let pixels = decoded.data!.assumingMemoryBound(to: UInt8.self)
        for pixel in 0..<12 {
            let offset = pixel * 4
            precondition(pixels[offset] == 0 && pixels[offset + 1] == 255
                         && pixels[offset + 2] == 0 && pixels[offset + 3] == 255,
                         "Reopening must decode the edited green image, not the original red image")
        }
        let permissions = try manager.attributesOfItem(atPath: imageURL.path)[.posixPermissions] as? NSNumber
        precondition(permissions?.intValue == 0o600)

        for (width, height) in [(5, 3), (4, 4)] {
            let resized = png(width: width, height: height, red: 0, green: 0, blue: 1)
            precondition(!service.replaceImage(at: imageURL, pngData: resized))
            precondition(service.lastError != nil)
            try assertUnchanged(imageURL, replacement)
        }
        precondition(!service.replaceImage(at: imageURL, pngData: Data("damaged PNG fixture".utf8)))
        precondition(service.lastError != nil)
        try assertUnchanged(imageURL, replacement)

        let outside = directory.appendingPathComponent(UUID().uuidString + ".png")
        try original.write(to: outside)
        precondition(!service.replaceImage(at: outside, pngData: replacement))
        precondition(service.lastError != nil)
        try assertUnchanged(outside, original)
        try assertUnchanged(imageURL, replacement)

        let symbolicLink = captures.appendingPathComponent(UUID().uuidString + ".png")
        try manager.createSymbolicLink(at: symbolicLink, withDestinationURL: outside)
        precondition(!service.replaceImage(at: symbolicLink, pngData: replacement))
        precondition(service.lastError != nil)
        let metadata = try symbolicLink.resourceValues(forKeys: [.isSymbolicLinkKey])
        precondition(metadata.isSymbolicLink == true, "Rejected replacement must not replace the link itself")
        try assertUnchanged(outside, original)
        try assertUnchanged(imageURL, replacement)

        // A rejected edit must not prevent a subsequent valid edit from being saved.
        precondition(service.replaceImage(at: imageURL, pngData: original))
        precondition(service.lastError == nil)
        try assertUnchanged(imageURL, original)
        print("Capture checks passed against production CaptureService.replaceImage: same-size PNG replacement and decoded pixels after reopening, private file permissions, width/height changes, damaged data, outside files and symbolic links rejected without changing originals, and recovery after rejection. Generated temporary images only; no screenshots, clipboard, save panel, permissions or desktop used.")
    }
}
