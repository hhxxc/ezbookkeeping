import SwiftUI
import UIKit

/// 「我的」页：账号信息、App 版本、后端版本、检查更新、退出登录
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthManager
    @ObservedObject private var updateStore = UpdateStore.shared
    @Environment(\.mainTabBarInset) private var tabBarInset

    @State private var showUpdateSheet = false
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationView {
            List {
                // 账号
                Section {
                    if let user = auth.currentUser {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(Theme.brand)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.nickname?.isEmpty == false ? user.nickname! : (user.username ?? "已登录"))
                                    .font(.headline)
                                if let email = user.email, !email.isEmpty {
                                    Text(email).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("已登录").foregroundColor(.secondary)
                    }
                    NavigationLink {
                        ProfileEditView()
                            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
                    } label: {
                        Label("个人资料", systemImage: "person.text.rectangle")
                    }
                }

                // 数据管理
                Section(header: Text("数据管理")) {
                    NavigationLink {
                        CategoriesView()
                            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
                    } label: {
                        Label("分类管理", systemImage: "square.grid.2x2")
                    }
                    NavigationLink {
                        TagsView()
                            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
                    } label: {
                        Label("标签管理", systemImage: "tag")
                    }
                    NavigationLink {
                        TemplatesView()
                            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
                    } label: {
                        Label("模板与计划账单", systemImage: "doc.on.doc")
                    }
                    NavigationLink {
                        DataManagementView()
                            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
                    } label: {
                        Label("数据管理", systemImage: "externaldrive")
                    }
                }

                // 页面与显示
                Section(header: Text("页面与显示")) {
                    NavigationLink {
                        PageSettingsView()
                    } label: {
                        Label("页面设置", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink {
                        TextSizeSettingsView()
                    } label: {
                        Label("字号", systemImage: "textformat.size")
                    }
                    NavigationLink {
                        AccountCategoryOrderView()
                    } label: {
                        Label("账户类别顺序", systemImage: "arrow.up.arrow.down")
                    }
                    NavigationLink {
                        AccountFilterSettingsView(type: "homePageOverview", title: "概览统计账户")
                    } label: {
                        Label("概览统计账户", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    NavigationLink {
                        CategoryFilterSettingsView(type: "homePageOverview", title: "概览统计分类")
                    } label: {
                        Label("概览统计分类", systemImage: "square.grid.2x2")
                    }
                    NavigationLink {
                        TagFilterSettingsView()
                    } label: {
                        Label("标签筛选", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }

                // 安全
                Section(header: Text("安全")) {
                    NavigationLink {
                        AppLockSettingsView()
                            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
                    } label: {
                        Label("应用锁", systemImage: "lock.shield")
                    }
                    NavigationLink {
                        TwoFactorAuthView()
                            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
                    } label: {
                        Label("两步验证", systemImage: "lock.rotation")
                    }
                    NavigationLink {
                        SessionsView()
                            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
                    } label: {
                        Label("设备与会话", systemImage: "iphone.gen3")
                    }
                }

                // 显示与汇率
                Section(header: Text("显示与汇率")) {
                    NavigationLink {
                        HomeBackgroundSettingsView()
                            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
                    } label: {
                        Label("首页背景图", systemImage: "photo")
                    }
                    NavigationLink {
                        ExchangeRatesView()
                            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
                    } label: {
                        Label("汇率", systemImage: "arrow.left.arrow.right")
                    }
                    NavigationLink {
                        BrowserCacheSettingsView()
                    } label: {
                        Label("缓存管理", systemImage: "internaldrive")
                    }
                    NavigationLink {
                        CloudSyncSettingsView()
                    } label: {
                        Label("设置云同步", systemImage: "icloud")
                    }
                }

                // 版本与更新
                Section(header: Text("关于")) {
                    HStack {
                        Text("App 版本")
                        Spacer()
                        Text("\(UpdateChecker.currentAppVersion) (\(UpdateChecker.currentBuildNumber))")
                            .foregroundColor(.secondary)
                    }

                    NavigationLink {
                        AboutView()
                            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
                    } label: {
                        Label("关于巢记", systemImage: "info.circle")
                    }

                    HStack {
                        Text("后端版本")
                        Spacer()
                        if let sv = updateStore.serverVersion, let v = sv.version {
                            Text(v).foregroundColor(.secondary)
                        } else {
                            Text("—").foregroundColor(.secondary)
                        }
                    }

                    Button {
                        showUpdateSheet = true
                        Task { await updateStore.checkNow() }
                    } label: {
                        HStack {
                            Text("检查更新")
                            Spacer()
                            if updateStore.isChecking {
                                ProgressView()
                            } else {
                                // 有新版时在右侧给个红点提示
                                if case .updateAvailable = updateStore.result {
                                    Circle().fill(Theme.expense).frame(width: 8, height: 8)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }

                // 退出登录
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        Text("退出登录").frame(maxWidth: .infinity)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: tabBarInset)
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showUpdateSheet) {
                UpdateResultSheet(updateStore: updateStore)
            }
            .confirmationDialog("确认退出登录？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) { auth.logout() }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

/// 检查更新结果弹层
struct UpdateResultSheet: View {
    @ObservedObject var updateStore: UpdateStore
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    /// 是否已展开分步引导（点「一键安装」后自动展开）
    @State private var showGuide = false

    /// 跳转 TrollStore 安装。
    ///
    /// 关于 `apple-magnifier` 的两个硬事实（决定了这里的设计）：
    /// 1. TrollStore 1.3+ **刻意用系统「放大器」的 scheme 替代自己的 scheme**
    ///    （规避越狱检测），且**没有提供任何自己的 URL scheme**。所以在装了
    ///    TrollStore 的设备上，调它会被系统转交 TrollStore 并弹安装确认；
    ///    在没有（或未接管）的设备上，就会**真的打开放大器**——这是设计如此，
    ///    不是 bug，App 侧无法区分、也无法阻止。
    /// 2. `UIApplication.open` 的 `opened` 回调**只表示"系统找到了处理者"**，
    ///    放大器也算处理者，所以 `opened == true` **不能作为"TrollStore 接住了"的依据**
    ///    （此前代码正是这么判的，导致兜底永远不触发、用户停在放大器）。
    ///
    /// 因此这里不再依赖 `opened` 做判断：无论跳转结果如何，都**同步给出兜底引导**
    /// （复制直链 + 分步说明），让用户无论如何都能完成安装。
    private func installToTrollStore(ipaURL: URL) {
        // 先复制直链：即使跳转失败用户也能直接去 TrollStore 粘贴。
        UIPasteboard.general.string = ipaURL.absoluteString
        copied = true
        showGuide = true

        var comp = URLComponents()
        comp.scheme = "apple-magnifier"
        comp.host = "install"
        comp.queryItems = [URLQueryItem(name: "url", value: ipaURL.absoluteString)]
        guard let trollURL = comp.url else { return }

        // 仍尝试一次跳转（成功的话 TrollStore 会直接弹安装确认，最省事）。
        // 不依赖回调结果做任何判断——系统层面无法区分放大器与 TrollStore。
        UIApplication.shared.open(trollURL, options: [:], completionHandler: nil)
    }

    /// 安装引导的一行：序号圆点 + 说明
    private func guideStep(_ index: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Theme.brand))
            Text(text)
                .font(.footnote)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Spacer()

                if updateStore.isChecking {
                    ProgressView()
                    Text("正在检查更新…").foregroundColor(.secondary)
                } else if let result = updateStore.result {
                    switch result {
                    case .upToDate(let current):
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 56))
                            .foregroundColor(Theme.income)
                        Text("已是最新版本").font(.title3.bold())
                        Text("当前版本 \(current)").foregroundColor(.secondary)

                    case .updateAvailable(let current, let latest, let releaseURL, let ipaURL):
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(Theme.brand)
                        Text("发现新版本 \(latest)").font(.title3.bold())
                        Text("当前版本 \(current)").foregroundColor(.secondary)

                        // 主按钮：尝试唤起 TrollStore 安装（走 apple-magnifier scheme）
                        if let ipaURL = ipaURL {
                            Button {
                                installToTrollStore(ipaURL: ipaURL)
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.down.app.fill")
                                    Text("一键安装到 TrollStore").bold()
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Theme.brand)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .padding(.horizontal, 32)

                            // 安装引导：无论跳转是否成功都给出来（方案已复制好）
                            if showGuide || copied {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("安装链接已复制。请按下面步骤完成安装：")
                                        .font(.footnote)
                                        .foregroundColor(Theme.brand)

                                    guideStep(1, "打开 TrollStore")
                                    guideStep(2, "点右上角「+」")
                                    guideStep(3, "选「从 URL 安装」，粘贴链接")
                                    guideStep(4, "确认安装（同变体才会覆盖旧版）")

                                    Text("提示：点按钮后如果跳到了「放大器」或什么都没发生，属正常现象——TrollStore 没有可被直接唤起的入口，用上面的方式粘贴安装即可。")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Theme.brand.opacity(0.08))
                                .cornerRadius(10)
                                .padding(.horizontal, 32)
                            } else {
                                Text("会尝试跳转 TrollStore 并弹出安装确认，同时自动复制安装链接。\n下载走你自己的服务器中转，不需要能访问 GitHub。")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }

                            // 次按钮：复制直链（一键安装不可用时的手动兜底）
                            Button {
                                UIPasteboard.general.string = ipaURL.absoluteString
                                copied = true
                                showGuide = true
                            } label: {
                                HStack {
                                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                                    Text(copied ? "已复制，去 TrollStore 粘贴安装" : "复制 IPA 直链").bold()
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Theme.brand.opacity(0.12))
                                .foregroundColor(Theme.brand)
                                .cornerRadius(12)
                            }
                            .padding(.horizontal, 32)
                        }

                        // 次按钮：打开发布页
                        if let releaseURL = releaseURL {
                            Link(destination: releaseURL) {
                                Text("打开发布页")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Theme.brand.opacity(0.12))
                                    .foregroundColor(Theme.brand)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal, 32)
                        }

                    case .failed(let message):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.orange)
                        Text("检查失败").font(.title3.bold())
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }

                Spacer()
            }
            .navigationTitle("检查更新")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onChange(of: updateStore.isChecking) { checking in
                // 新一轮检查开始时才重置复制/引导状态；结束时不重置，
                // 否则会清掉「一键安装」刚设置的引导提示。
                if checking {
                    copied = false
                    showGuide = false
                }
            }
        }
    }
}
