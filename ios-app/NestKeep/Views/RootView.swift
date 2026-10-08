import SwiftUI
import UIKit

/// 根据登录态 / 应用锁状态在「登录页」「解锁页」「主界面」之间切换
struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    @ObservedObject private var lock = AppLockManager.shared

    var body: some View {
        Group {
            if !auth.isLoggedIn {
                LoginView()
            } else if lock.isEnabled && !lock.isUnlocked {
                AppLockView()
            } else {
                MainTabView()
            }
        }
        // 进入后台时自动锁定（回到前台需重新解锁）
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            lock.lock()
        }
    }
}
