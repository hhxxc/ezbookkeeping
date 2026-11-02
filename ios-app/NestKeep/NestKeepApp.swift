import SwiftUI

@main
struct NestKeepApp: App {
    @StateObject private var auth = AuthManager.shared
    @StateObject private var settings = AppSettings.shared

    init() {
        // 全局隐藏滚动指示条（上下滑动时右侧不出现滚动条）。
        // 用 UIAppearance 兼容旧 SDK（.indicator(.hidden) 需更新的 SDK），
        // 对之后创建的所有 UIScrollView（List/ScrollView/Form）生效。
        UIScrollView.appearance().showsVerticalScrollIndicator = false
        UIScrollView.appearance().showsHorizontalScrollIndicator = false
        // 冷启动打点：此刻已包含 @StateObject 属性初始化（AuthManager Keychain 恢复等）
        StartupMetrics.shared.markOnce("app-init")
        // 强制在明确的 MainActor 上下文初始化截屏监听单例：它的 static let shared
        // 是 @MainActor 隔离，若只在 MainTabView(struct) 的默认成员初始化器里惰性访问，
        // 非隔离上下文可能导致初始化延迟/失败，通知注册不上，截屏永远无反应。
        _ = ScreenshotWatcher.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(settings)
        }
    }
}
