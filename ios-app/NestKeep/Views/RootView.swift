import SwiftUI

/// 根据登录态在「登录页」与「主界面」之间切换
struct RootView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        if auth.isLoggedIn {
            MainTabView()
        } else {
            LoginView()
        }
    }
}
