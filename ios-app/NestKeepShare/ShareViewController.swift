import UIKit
import UniformTypeIdentifiers
import Foundation

/// 系统分享扩展入口：用户在相册/截图里点「分享 → 巢记」，把图片压缩后写入
/// App Group 共享目录，再用 URL Scheme 唤醒主 App 进识图页。
///
/// ## 与主 App 的通信链路
/// 1. 本扩展读取分享进来的图片（`NSExtensionItem` → `NSItemProvider`）；
/// 2. 长边压到 ≤1280px、JPEG q0.75（与主 App 识图同口径）；
/// 3. 写进 App Group 共享容器目录（`group.com.nestkeep.app.dev`），文件名带时间戳；
/// 4. 在共享 UserDefaults 写一个「待识别」标记（图片文件路径列表）；
/// 5. `extensionContext.open(nestkeep://receipt)` 唤醒主 App → 主 App 读图进识图页；
/// 6. 结束扩展（`completeRequest`）。
///
/// ## 为什么不用 UserDefaults 直接传图 Data
/// App Group 的 UserDefaults 不适合塞大图（内存/性能差），图片走共享容器文件、
/// 标记只存文件名列表，主 App 按列表读文件。这是 Share Extension 传图的通行做法。
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        handleSharedItems()
    }

    private func handleSharedItems() {
        guard let extensionContext = extensionContext else {
            finish()
            return
        }
        let items = extensionContext.inputItems.compactMap { $0 as? NSExtensionItem }
        let providers = items.flatMap { $0.attachments ?? [] }

        guard !providers.isEmpty else {
            finish()
            return
        }

        // 收集所有图片（异步，可能多张）
        var imagesData: [Data] = []
        let group = DispatchGroup()
        let lock = NSLock()

        for provider in providers {
            group.enter()
            loadImage(from: provider) { data in
                if let data {
                    lock.lock()
                    imagesData.append(data)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if imagesData.isEmpty {
                self.finish()
                return
            }
            self.persistAndOpen(imagesData)
        }
    }

    /// 从 NSItemProvider 取图片（支持 UIImage 与 URL 两种负载）。
    private func loadImage(from provider: NSItemProvider, completion: @escaping (Data?) -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                let data = Self.imageData(from: item)
                DispatchQueue.main.async { completion(data) }
            }
        } else {
            // 兜底：尝试公开图片类型
            provider.loadItem(forTypeIdentifier: "public.image", options: nil) { item, _ in
                let data = Self.imageData(from: item)
                DispatchQueue.main.async { completion(data) }
            }
        }
    }

    /// 把 NSItemProvider 返回的负载（UIImage / URL / Data）统一转成压缩后的 JPEG Data。
    private static func imageData(from item: NSSecureCoding?) -> Data? {
        var image: UIImage?
        if let url = item as? URL {
            image = UIImage(contentsOfFile: url.path)
        } else if let img = item as? UIImage {
            image = img
        } else if let data = item as? Data {
            image = UIImage(data: data)
        }
        guard let image else { return nil }
        return compressedData(image)
    }

    /// 压到长边 ≤1280px 再编码 JPEG q0.75（与主 App 识图同口径）。
    private static func compressedData(_ image: UIImage) -> Data? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longEdge = max(pixelWidth, pixelHeight)
        let maxEdge: CGFloat = 1280
        if longEdge > maxEdge {
            let ratio = maxEdge / longEdge
            let newSize = CGSize(width: pixelWidth * ratio, height: pixelHeight * ratio)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let scaled = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
            return scaled.jpegData(compressionQuality: 0.75)
        }
        return image.jpegData(compressionQuality: 0.75)
    }

    /// 写共享目录 + 标记 → 结束扩展。
    /// ⚠️ Share Extension 无法 `openURL` 唤醒宿主 App（NSExtensionContext.open 对
    /// Share Extension 不可用，系统层面禁止）。图片已写入 App Group 共享容器，
    /// 用户切回巢记时由主 App 在回前台时消费进识图页。
    private func persistAndOpen(_ imagesData: [Data]) {
        ShareReceiptStore.savePendingImages(imagesData)
        finish()
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

/// Share Extension 与主 App 共享的「待识别图片」存储（App Group 共享容器）。
///
/// ⚠️ 与主 App 内 `ShareReceiptStore` 保持字段/路径/键名完全一致（两 target 独立编译，
/// Swift 无法跨 target 复用非模块代码，这里有意保留镜像定义，与 WidgetSnapshot 同理）。
enum ShareReceiptStore {
    /// 待识别图片文件名列表的 UserDefaults 键。
    static let pendingKey = "nestkeep.share.pendingImages"

    /// App Group 按 bundle id 推导（com.nestkeep.app.dev.share → group.com.nestkeep.app.dev）。
    /// dev/pro 双 flavor 通用。
    static var groupIdentifier: String {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.nestkeep.app.dev.share"
        let base = bundleId.hasSuffix(".share")
            ? String(bundleId.dropLast(".share".count))
            : bundleId
        return "group." + base
    }

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: groupIdentifier)
    }

    /// 共享容器目录（图片文件存放处）。
    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    /// 把图片写入共享容器，并把文件名列表写入共享 UserDefaults。
    static func savePendingImages(_ datas: [Data]) {
        guard let container = sharedContainerURL else { return }
        let dir = container.appendingPathComponent("ShareReceipt", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var filenames: [String] = []
        for data in datas {
            let name = "share-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(6)).jpg"
            let url = dir.appendingPathComponent(name)
            if (try? data.write(to: url)) != nil {
                filenames.append(name)
            }
        }
        // 只保留文件名（路径由主 App 重新拼容器目录），避免跨进程绝对路径不一致
        sharedDefaults?.set(filenames, forKey: pendingKey)
    }
}
