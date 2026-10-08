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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(settings)
        }
    }
}
