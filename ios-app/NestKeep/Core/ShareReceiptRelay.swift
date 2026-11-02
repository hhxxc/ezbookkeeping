import Foundation
import Combine

/// 深链中转：Share Extension 唤醒主 App 后，主 App 读到待识别图片，通过本单例
/// 发布给 MainTabView，触发进识图页。
///
/// 为什么用单例而不是 @State 层层传参：nestkeep://receipt 的深链在 NestKeepApp
/// 层用 .onOpenURL 接收，而识图流程 aiFlow 挂在 MainTabView 内部。中间隔了
/// RootView（可能还在登录页/锁屏页），直接传参要跨多层。用 ObservableObject 单例
/// 做一次性事件中转最干净：MainTabView 挂载后订阅，未挂载时先缓存，挂载后消费。
final class ShareReceiptRelay: ObservableObject {
    static let shared = ShareReceiptRelay()

    /// 待识别的图片批次（非空时 MainTabView 应消费并进识图页）。
    @Published private(set) var pendingImages: [Data] = []

    /// 深链触发：读共享容器里的图片并发布。
    func deliverFromShareExtension() {
        let datas = ShareReceiptStore.consumePendingImages()
        guard !datas.isEmpty else { return }
        pendingImages = datas
    }

    /// 深链触发但此时无待识别图片（可能扩展还没写完，稍后重试一次）。
    func deliverPendingLater() {
        // 扩展先写文件再 open URL，理论上 open 时文件已就绪；若极端竞态读空，
        // 这里留空实现，由 MainTabView 的 onAppear 兜底再读一次。
    }

    /// 上层消费完后复位。
    func clear() {
        pendingImages = []
    }
}
