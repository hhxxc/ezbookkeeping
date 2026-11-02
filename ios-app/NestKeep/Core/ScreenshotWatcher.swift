import Foundation
import UIKit
import Photos

/// 截屏监听：用户截屏后自动收集刚产生的截图，回调给上层弹「识别刚截的图？」提示。
///
/// iOS 没有「读取当前屏幕画面」的公开能力，`userDidTakeScreenshotNotification`
/// 也**不携带截图数据**，且只在 App **前台**时送达——用户在微信/支付宝里截屏时
/// 收不到通知。本组件通过「截屏通知 + 回前台扫相册」两条路径拼出闭环：
///   1. `UIApplication.userDidTakeScreenshotNotification` —— App 前台截屏时即时感知；
///   2. `UIApplication.willEnterForegroundNotification` —— 回前台时扫相册最近窗口内
///      新增的截图，兜底「在别的 App 截屏后切回」这一主场景（通知是否补触发因 iOS
///      版本而异，不能依赖，扫相册才可靠）。
///
/// ## 连续截屏与去重
/// 用户连截多张时通知/扫描会连着触发，若每次立刻取图会「取错图」或「同一张识别
/// 多遍」。做法：
///   - 静默窗口：触发后进入可延长窗口，窗口内再有截屏就重置计时，把连拍聚合一批；
///   - 时间戳去重：记录已回调过的批次时间点，回前台扫描时跳过已处理的截图。
@MainActor
final class ScreenshotWatcher: NSObject, ObservableObject {
    static let shared = ScreenshotWatcher()

    /// 截屏批次收集完成后的回调（主线程）。参数为本次批次的图片数据（可能为空）。
    var onBatchCollected: (([Data]) -> Void)?

    /// 静默窗口时长：这段时间内再有截屏就重置计时，把连拍合并成一批。
    private let debounceInterval: TimeInterval = 1.5

    /// 截屏后等相册落盘再查新增的延时（截图写入相册是异步的）。
    private let photoSettleDelay: TimeInterval = 0.4

    /// 回前台扫描时，认「最近多少秒内」新增的截图。
    private let foregroundScanWindow: TimeInterval = 120

    /// 静默窗口计时任务。
    private var debounceWorkItem: DispatchWorkItem?

    /// 是否正在收集（防止连续触发重叠）。
    private var isCollecting = false

    /// 已回调过的批次时间戳（去重：回前台扫描跳过此时间点之前的截图）。
    private var lastHandledDate: Date = .distantPast

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
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 触发源

    @objc private func handleScreenshot() {
        scheduleDebounce()
    }

    /// 回前台：扫相册最近窗口内新增的截图，兜底「别的 App 截屏后切回」场景。
    @objc private func handleForeground() {
        // 回前台也走静默窗口：切回 App 到相册可读之间可能还有新截图落盘
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
            queryRecentScreenshots()
        case .notDetermined:
            requestAndCollect()
        case .denied, .restricted:
            // 无权限：清空并回调空数组，上层无需弹提示（授权需用户去系统设置开启）
            isCollecting = false
            onBatchCollected?([])
        @unknown default:
            isCollecting = false
            onBatchCollected?([])
        }
    }

    private func requestAndCollect() {
        let handler: (PHAuthorizationStatus) -> Void = { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCollecting = false
                if status == .authorized || status == .limited {
                    self.queryRecentScreenshots()
                } else {
                    self.onBatchCollected?([])
                }
            }
        }
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .readWrite, handler: handler)
        } else {
            PHPhotoLibrary.requestAuthorization(handler)
        }
    }

    /// 查相册「最近窗口期内」新增的截图（按创建时间过滤，并跳过已处理的）。
    private func queryRecentScreenshots() {
        DispatchQueue.main.asyncAfter(deadline: .now() + photoSettleDelay) { [weak self] in
            guard let self else { return }
            self.fetchScreenshots { datas in
                self.isCollecting = false
                self.onBatchCollected?(datas)
            }
        }
    }

    /// 从相册取「上次处理后到现在」新增的截图，转成 Data（长边压缩对齐识图口径）。
    /// 回前台扫描窗口比静默窗口长（用户可能在别的 App 里截屏后隔一会儿才切回）。
    private func fetchScreenshots(completion: @escaping ([Data]) -> Void) {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // 起始点 = 上次处理时刻；但回前台场景上次处理可能很久以前，用扫描窗口兜底，
        // 避免把几小时前无关截图误认成「刚截的」
        let floor = Date().addingTimeInterval(-foregroundScanWindow)
        let since = max(lastHandledDate, floor)
        options.predicate = NSPredicate(format: "creationDate >= %@", since as NSDate)

        let assets = PHAsset.fetchAssets(with: .image, options: options)

        // 最多 9 张（对齐识图多选上限），fetch 默认降序，反转为升序（连截顺序）
        var collected: [PHAsset] = []
        assets.enumerateObjects { asset, _, stop in
            collected.append(asset)
            if collected.count >= 9 {
                stop.pointee = true
            }
        }
        collected.reverse()

        guard !collected.isEmpty else {
            completion([])
            return
        }

        // 无论最终是否回调非空，先把「本次扫描基准」推进到最新截图时间，避免重复扫
        let latestDate = collected.map { $0.creationDate ?? Date() }.max() ?? Date()
        lastHandledDate = latestDate

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

        group.notify(queue: .main) {
            completion(slots.compactMap { $0 })
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
