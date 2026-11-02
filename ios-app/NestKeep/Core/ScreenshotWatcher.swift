import Foundation
import UIKit
import Photos

/// 截屏监听：用户截屏后自动收集刚产生的截图，回调给上层弹「识别刚截的图？」提示。
///
/// iOS 没有「读取当前屏幕画面」的公开能力，`userDidTakeScreenshotNotification`
/// 也**不携带截图数据**，且只在 App **前台**时送达——用户在微信/支付宝里截屏时
/// 收不到通知。本组件用三条触发路径拼出闭环：
///   1. `UIApplication.userDidTakeScreenshotNotification` —— App 前台截屏时即时感知；
///   2. `UIApplication.willEnterForegroundNotification` —— 回前台时扫相册最近窗口内
///      新增的截图，兜底「在别的 App 截屏后切回」这一主场景；
///   3. `PHPhotoLibraryChangeObserver` —— 截屏写入相册时系统派发变化通知，最可靠。
///
/// ## 关键实现（对齐业界验证过的方案）
/// - **精确过滤截图**：predicate 加 `mediaSubtype & photoScreenshot != 0`，只认截图
///   资产，不会把相册里最近的普通照片误认成「刚截的」；
/// - **有界重试**：截图写入相册与通知/回前台之间存在竞态（assets 可能还没落盘），
///   第一次查不到就延时 750ms 再查一次，而不是只查一次就放弃；
/// - **assetID 精确去重**：记录已回调过的截图 localIdentifier，避免同一张反复弹。
///
/// ## 为什么不用 @MainActor
/// 之前标了 @MainActor，`static let shared` 变成 MainActor 隔离的静态属性，在
/// `MainTabView`(struct) 的默认成员初始化器（非隔离上下文）里惰性访问会触发
/// 隐式跳转/延迟初始化，导致单例可能没真正注册通知——真机「截屏完全没反应、
/// 诊断横幅都不显示」的根因。改成普通 final class，所有 @Published 更新统一
/// 在主线程（通知本身主线程派发，PHPhotoLibraryChangeObserver 回调手动 main.async）。
final class ScreenshotWatcher: NSObject, ObservableObject {
    static let shared = ScreenshotWatcher()

    /// 收集到的截图批次（@Published 供 SwiftUI 订阅，避免 struct 闭包捕获 self 的坑）。
    /// 值为非空数组时表示有一批新截图待处理；上层消费后调用 clearPending() 复位。
    @Published private(set) var pendingBatch: [Data] = []

    /// 统一交付批次：发布 @Published。
    private func deliver(_ datas: [Data]) {
        pendingBatch = datas
    }

    /// 静默窗口时长：这段时间内再有截屏就重置计时，把连拍合并成一批。
    private let debounceInterval: TimeInterval = 1.2

    /// 回前台扫描时，认「最近多少秒内」新增的截图。
    private let foregroundScanWindow: TimeInterval = 120

    /// 静默窗口计时任务。
    private var debounceWorkItem: DispatchWorkItem?

    /// 是否正在收集（防止连续触发重叠）。
    private var isCollecting = false

    /// 已回调过的截图 localIdentifier（精确去重，替代模糊的时间戳）。
    private var handledIdentifiers: Set<String> = []

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenshot),
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForeground),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // MARK: - 触发源

    @objc private func handleScreenshot() {
        scheduleDebounce()
    }

    /// 回前台：扫相册最近窗口内新增的截图，兜底「别的 App 截屏后切回」场景。
    @objc private func handleForeground() {
        scheduleDebounce()
    }

    /// 静默窗口：重置计时，把连拍/切回聚合进同一批。
    private func scheduleDebounce() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.collectScreenshots()
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    // MARK: - 权限与收集

    private func collectScreenshots() {
        guard !isCollecting else { return }
        isCollecting = true

        let status: PHAuthorizationStatus
        if #available(iOS 14, *) {
            status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        } else {
            status = PHPhotoLibrary.authorizationStatus()
        }

        switch status {
        case .authorized, .limited:
            fetchScreenshots(retry: true)
        case .notDetermined:
            requestAndCollect()
        case .denied, .restricted:
            isCollecting = false
            deliver([])
        @unknown default:
            isCollecting = false
            deliver([])
        }
    }

    /// 上层消费完批次后复位（供下次截屏重新发布）。
    func clearPending() {
        pendingBatch = []
    }

    private func requestAndCollect() {
        let handler: (PHAuthorizationStatus) -> Void = { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCollecting = false
                if status == .authorized || status == .limited {
                    self.fetchScreenshots(retry: true)
                } else {
                    self.deliver([])
                }
            }
        }
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .readWrite, handler: handler)
        } else {
            PHPhotoLibrary.requestAuthorization(handler)
        }
    }

    // MARK: - 扫相册

    /// 扫相册最近窗口内**新增的截图**（精确过滤 + assetID 去重 + 有界重试）。
    /// - Parameter retry: 查不到时是否延时重试一次（截图落盘竞态）。
    private func fetchScreenshots(retry: Bool) {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let since = Date().addingTimeInterval(-foregroundScanWindow)
        // 关键：精确过滤「截图」资产，避免误扫普通照片。
        // ⚠️ PHAsset 的查询 key 是「mediaSubtype」(单数)——PHFetchOptions 的 predicate
        //    走 Core Data 键值，写错成 mediaSubtypes(复数) 会导致查询恒返回空集，
        //    这是之前「截屏后完全没反应」的根因。
        options.predicate = NSPredicate(
            format: "(mediaSubtype & %d) != 0 AND creationDate >= %@",
            PHAssetMediaSubtype.photoScreenshot.rawValue, since as NSDate
        )

        let assets = PHAsset.fetchAssets(with: .image, options: options)

        // 收集「未处理过的」截图，按创建时间升序（连截顺序），最多 9 张
        var collected: [PHAsset] = []
        assets.enumerateObjects { asset, _, stop in
            let id = asset.localIdentifier
            if !self.handledIdentifiers.contains(id) {
                collected.append(asset)
            }
            if collected.count >= 9 {
                stop.pointee = true
            }
        }
        collected.reverse()

        guard !collected.isEmpty else {
            // 截图落盘竞态：第一次查不到，延时再查一次（有界重试）
            if retry {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                    self?.fetchScreenshots(retry: false)
                }
            } else {
                isCollecting = false
                deliver([])
            }
            return
        }

        // 立即登记为「已处理」，防止重试/下次扫描重复收集
        for asset in collected {
            handledIdentifiers.insert(asset.localIdentifier)
        }

        // 防止去重集合无限增长：超过 1000 条时清理（保留最近的行为依赖，这里简单重置）
        if handledIdentifiers.count > 1000 {
            handledIdentifiers.removeAll()
        }

        let manager = PHImageManager.default()
        let reqOptions = PHImageRequestOptions()
        reqOptions.isSynchronous = false
        reqOptions.deliveryMode = .highQualityFormat
        reqOptions.isNetworkAccessAllowed = true
        let targetSize = CGSize(width: 1280, height: 1280)

        let lock = NSLock()
        var slots = [Data?](repeating: nil, count: collected.count)
        let group = DispatchGroup()

        for (index, asset) in collected.enumerated() {
            group.enter()
            manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: reqOptions) { image, _ in
                if let image, let data = ScreenshotWatcher.compressedData(image) {
                    lock.lock()
                    slots[index] = data
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isCollecting = false
            let result = slots.compactMap { $0 }
            self.deliver(result)
        }
    }

    /// 压到长边 ≤1280px 再编码 JPEG q0.75（与 ReceiptPhotoPicker.compressedData 同口径）。
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
}

// MARK: - PHPhotoLibraryChangeObserver

extension ScreenshotWatcher: PHPhotoLibraryChangeObserver {
    /// 截屏写入相册时系统派发的变化通知——比截屏通知/回前台更可靠的触发源。
    /// 该方法在**非主线程**回调，手动转到主线程走静默窗口聚合（@Published 更新
    /// 必须在主线程）。
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            self?.scheduleDebounce()
        }
    }
}
