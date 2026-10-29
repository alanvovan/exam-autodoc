import ImageIO
import UIKit

actor ImageLoader {
    static let shared = ImageLoader()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let session: URLSession

    init() {
        let storage = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = storage
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
        memoryCache.countLimit = 180
    }

    func image(for url: URL, pointSize: CGSize, scale: CGFloat) async -> UIImage? {
        let pixelWidth = max(pointSize.width, 1) * max(scale, 1)
        let pixelHeight = max(pointSize.height, 1) * max(scale, 1)
        let key = "\(url.absoluteString)|\(Int(pixelWidth))x\(Int(pixelHeight))" as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        let data: Data
        do {
            let (downloaded, response) = try await session.data(from: url)
            guard !Task.isCancelled else { return nil }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            data = downloaded
        } catch {
            return nil
        }

        guard !Task.isCancelled else { return nil }
        let thumbnail = await Self.thumbnail(data: data, maxPixel: max(pixelWidth, pixelHeight), scale: scale)
        if let thumbnail {
            memoryCache.setObject(thumbnail, forKey: key)
        }
        return thumbnail
    }

    private static func thumbnail(data: Data, maxPixel: CGFloat, scale: CGFloat) async -> UIImage? {
        let maxPixel = max(maxPixel, 1)
        return await Task.detached(priority: .userInitiated) {
            // Уменьшаем до размера ячейки, чтобы не декодировать полный JPEG в ленте.
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
            }
            return UIImage(data: data)
        }.value
    }
}
