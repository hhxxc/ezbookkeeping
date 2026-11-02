import Foundation
import UIKit

/// 主 App 侧：读取 Share Extension 写入 App Group 的「待识别图片」。
///
/// ⚠️ 与 Share Extension 内的同名类型保持字段/路径/键名完全一致（两 target 独立
/// 编译，Swift 无法跨 target 复用非模块代码，这里有意保留镜像定义，与 WidgetSnapshot
/// 同理）。extension 侧是 `enum` 只负责写，主 App 侧额外提供读方法。
enum ShareReceiptStore {
    /// 待识别图片文件名列表的 UserDefaults 键。
    static let pendingKey = "nestkeep.share.pendingImages"

    /// App Group 按 bundle id 推导（com.nestkeep.app.dev → group.com.nestkeep.app.dev）。
    /// dev/pro 双 flavor 通用。
    static var groupIdentifier: String {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.nestkeep.app.dev"
        return "group." + bundleId
    }

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: groupIdentifier)
    }

    /// 共享容器目录（图片文件存放处）。
    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    /// 读取待识别图片（按文件名列表从共享容器读文件 → Data）。
    /// 读完后清空标记，避免下次误触发。
    static func consumePendingImages() -> [Data] {
        guard let defaults = sharedDefaults,
              let filenames = defaults.array(forKey: pendingKey) as? [String],
              let container = sharedContainerURL else {
            return []
        }
        let dir = container.appendingPathComponent("ShareReceipt", isDirectory: true)
        var datas: [Data] = []
        for name in filenames {
            let url = dir.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url) {
                datas.append(data)
            }
        }
        // 清空标记（图片文件留在容器，下次写入会生成新文件名，旧的会被覆盖/残留，
        // 这里顺带清理已消费的文件，避免共享容器膨胀）
        defaults.removeObject(forKey: pendingKey)
        for name in filenames {
            let url = dir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
        }
        return datas
    }

    /// 是否有待识别图片（供启动时判断是否需要跳转）。
    static func hasPendingImages() -> Bool {
        guard let defaults = sharedDefaults,
              let filenames = defaults.array(forKey: pendingKey) as? [String] else {
            return false
        }
        return !filenames.isEmpty
    }
}
