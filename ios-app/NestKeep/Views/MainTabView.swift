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

            PlaceholderView(title: "我的", systemImage: "person.fill")
                .tabItem { Label("我的", systemImage: "person.fill") }
        }
        .accentColor(Theme.brand)
    }
}

/// 临时占位页（下一轮替换为「我的/设置」）
struct PlaceholderView: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Image(systemName: systemImage).font(.largeTitle).foregroundColor(.secondary)
                Text("「\(title)」页面将在后续阶段实现")
                    .foregroundColor(.secondary)
            }
            .navigationTitle(title)
        }
    }
}
