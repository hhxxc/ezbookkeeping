import SwiftUI

/// 主界面底部 Tab：首页 / 账户 / 账单 / 我的。完全原生 iOS 风格
struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }

            AccountsView()
                .tabItem { Label("账户", systemImage: "wallet.pass") }

            TransactionsView()
                .tabItem { Label("账单", systemImage: "list.bullet") }

            SettingsView()
                .tabItem { Label("我的", systemImage: "person.fill") }
        }
        .accentColor(Theme.brand)
        // 启动时静默检查更新（有间隔节流，失败不打扰）
        .task { await UpdateStore.shared.autoCheckIfNeeded() }
    }
}
