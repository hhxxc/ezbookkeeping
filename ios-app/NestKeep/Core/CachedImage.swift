import SwiftUI
import UIKit

/// 带磁盘/内存缓存的异步图片加载组件。
///
/// 背景：首页汇总卡的背景图 URL 带 `?token=` 鉴权参数，直接用系统 `AsyncImage`
/// （`URLSession.shared`）在 `List` 滚动时会反复卸载/重载，且默认缓存较小，
/// 容易造成背景图「闪一下 / 偶尔加载不出来」。这里换成独立配置了 `URLCache`
/// 的 URLSession，按 URL 缓存图片数据，滚动不再重复请求。
@MainActor
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let scale: CGFloat
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @StateObject private var loader = ImageLoader()

    init(url: URL?, scale: CGFloat = 1,
         @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.scale = scale
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = loader.image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .onAppear { loader.load(url: url, scale: scale) }
        .onChange(of: url) { newURL in
            loader.load(url: newURL, scale: scale)
        }
    }
}

/// 图片加载器：共享一个配置了磁盘缓存的 URLSession，按 URL 缓存结果。
@MainActor
final class ImageLoader: ObservableObject {
    @Published var image: UIImage?

    private static let cache: URLCache = {
        let mem = 24 * 1024 * 1024
        let disk = 96 * 1024 * 1024
        let c = URLCache(memoryCapacity: mem, diskCapacity: disk, diskPath: "nestkeep.imageCache")
        return c
    }()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private var currentURL: URL?

    func load(url: URL?, scale: CGFloat) {
        guard let url = url else {
            image = nil
            return
        }
        // 同一 URL 不重复加载
        guard url != currentURL else { return }
        currentURL = url
        image = nil

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad

        Self.session.dataTask(with: request) { data, _, _ in
            guard let data = data, let img = UIImage(data: data, scale: scale) else { return }
            Task { @MainActor [weak self] in
                self?.image = img
            }
        }.resume()
    }
}
