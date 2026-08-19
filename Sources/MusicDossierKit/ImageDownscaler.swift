import CoreGraphics
import Foundation
import ImageIO

/// 把下载的图缩到合理尺寸再落盘，避免维基百科原图（动辄 10MB+）撑爆缓存。
public enum ImageDownscaler {
    /// 返回缩放/重压缩后的 JPEG（或原数据，如果已经够小）与扩展名。
    public static func downscale(_ data: Data, maxPixel: CGFloat, quality: CGFloat = 0.82) -> (data: Data, fileExtension: String) {
        let originalExtension = ImageSniffing.detectedFileExtension(for: data) ?? "jpg"
        // 小文件且尺寸未知：直接看像素
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat
        else {
            return (data, originalExtension)
        }

        let longest = max(width, height)
        let needsResize = longest > maxPixel
        let needsRecompress = data.count > 600_000 || (originalExtension != "jpg" && originalExtension != "jpeg" && data.count > 200_000)
        guard needsResize || needsRecompress else {
            return (data, originalExtension)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: needsResize ? maxPixel : longest,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return (data, originalExtension)
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            return (data, originalExtension)
        }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length > 0 else {
            return (data, originalExtension)
        }
        return (output as Data, "jpg")
    }
}
