import ImageIO
import SwiftUI
import UIKit

/// Native HTTP caching plus bounded decoded thumbnails; identical in-flight URLs share work.
actor ExploreImageCache {
    static let shared = ExploreImageCache()
    private let cache = NSCache<NSURL, UIImage>()
    private var pending: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    init() {
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 120
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024, diskPath: "explore-images")
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    func image(url: URL) async -> UIImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        if let task = pending[url] { return await task.value }
        let task = Task { await download(url: url) }
        pending[url] = task
        let image = await task.value
        pending[url] = nil
        if let image {
            cache.setObject(image, forKey: url as NSURL, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
        }
        return image
    }

    private func download(url: URL) async -> UIImage? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count <= 12 * 1024 * 1024,
                  let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 600,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: thumbnail)
        } catch {
            #if DEBUG
            print("Explore image failed: \(String(reflecting: error))")
            #endif
            return nil
        }
    }
}

struct ExploreRecipeImage: View {
    let path: String?
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(HomeyColors.primary.opacity(0.08))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else {
                        Image(systemName: "fork.knife")
                            .font(.title2)
                            .foregroundStyle(HomeyColors.primary.opacity(0.45))
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .onDisappear { image = nil }
            .task(id: path) {
                image = nil
                guard let url = await MealsService().signedImageURL(path: path) else { return }
                let loaded = await ExploreImageCache.shared.image(url: url)
                guard !Task.isCancelled else { return }
                image = loaded
            }
    }
}
