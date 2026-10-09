import SwiftUI
import UIKit

/// 「我的」页：账号信息、App 版本、后端版本、检查更新、退出登录
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthManager
    @ObservedObject private var updateStore = UpdateStore.shared

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
                    } label: {
                        Label("个人资料", systemImage: "person.text.rectangle")
                    }
                }

                // 数据管理
                Section(header: Text("数据管理")) {
                    NavigationLink {
                        CategoriesView()
                    } label: {
                        Label("分类管理", systemImage: "square.grid.2x2")
                    }
                    NavigationLink {
                        TagsView()
                    } label: {
                        Label("标签管理", systemImage: "tag")
                    }
                    NavigationLink {
                        TemplatesView()
                    } label: {
                        Label("模板与计划账单", systemImage: "doc.on.doc")
                    }
                    NavigationLink {
                        DataManagementView()
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
                    } label: {
                        Label("应用锁", systemImage: "lock.shield")
                    }
                    NavigationLink {
                        TwoFactorAuthView()
                    } label: {
                        Label("两步验证", systemImage: "lock.rotation")
                    }
                    NavigationLink {
                        SessionsView()
                    } label: {
                        Label("设备与会话", systemImage: "iphone.gen3")
                    }
                }

                // 显示与汇率
                Section(header: Text("显示与汇率")) {
                    NavigationLink {
                        HomeBackgroundSettingsView()
                    } label: {
                        Label("首页背景图", systemImage: "photo")
                    }
                    NavigationLink {
                        ExchangeRatesView()
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
            // 底部避让由 MainTabView 整页容器统一施加，此处不再重复叠加
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
    /// 是否已展开分步引导（点「直接唤起」后自动展开）
    @State private var showGuide = false
    /// 交给系统面板的文档控制器（必须强引用，否则面板秒关）
    @State private var docController: UIDocumentInteractionController?
    @State private var docHost = DocControllerHost()
    @State private var showNoTrollStoreAlert = false

    /// 换源后的最优安装直链（复制/唤起都用它，避免把 github.com 原链交给用户）。
    private func bestInstallURL(_ ipaURL: URL, version: String) -> URL {
        UpdateChecker.downloadCandidates(ipaURL: ipaURL, version: version).first ?? ipaURL
    }

    /// 跳转 TrollStore 安装（**备用路径**，主路径是「App 内下载 → 系统面板」）。
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
    private func installToTrollStore(ipaURL: URL, version: String) {
        // 先复制直链（换源后的最优地址）：即使跳转失败用户也能直接去 TrollStore 粘贴。
        let best = bestInstallURL(ipaURL, version: version)
        UIPasteboard.general.string = best.absoluteString
        copied = true
        showGuide = true

        var comp = URLComponents()
        comp.scheme = "apple-magnifier"
        comp.host = "install"
        comp.queryItems = [URLQueryItem(name: "url", value: best.absoluteString)]
        guard let trollURL = comp.url else { return }

        // 仍尝试一次跳转（成功的话 TrollStore 会直接弹安装确认，最省事）。
        // 不依赖回调结果做任何判断——系统层面无法区分放大器与 TrollStore。
        UIApplication.shared.open(trollURL, options: [:], completionHandler: nil)
    }

    /// 把已下载的 IPA 交给系统「打开方式」面板，由用户选择 TrollStore 完成安装。
    ///
    /// TrollStore 注册了 .ipa/.tipa 文件类型（文件 App 里「分享 → TrollStore」走的
    /// 就是这条路），**不依赖 apple-magnifier scheme 的接管状态**，在哪台装了
    /// TrollStore 的设备上都能用。
    private func openInstallPanel(_ fileURL: URL) {
        let dic = UIDocumentInteractionController(url: fileURL)
        dic.delegate = docHost
        docController = dic

        guard let topVC = topPresentedViewController(), let view = topVC.view else {
            showNoTrollStoreAlert = true
            return
        }
        // 先试「打开方式」面板（只列声明了 .ipa 类型的 App，即 TrollStore）；
        // 无可用 App 时再试完整分享面板，仍不行才报错。
        if dic.presentOpenInMenu(from: view.bounds, in: view, animated: true) { return }
        if dic.presentOptionsMenu(from: view.bounds, in: view, animated: true) { return }
        docController = nil
        showNoTrollStoreAlert = true
    }

    /// 当前最上层 VC（更新弹层本身也是被 present 的，必须锚到它上面）。
    private func topPresentedViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
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

    // MARK: - 安装控件（App 内下载 → 系统面板交给 TrollStore）

    /// 主按钮：品牌色大按钮
    private func primaryButton(icon: String, title: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title).bold()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Theme.brand)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding(.horizontal, 32)
    }

    private func byteText(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    /// 按 IPA 下载状态渲染主路径控件（下载中 / 完成 / 失败各一态）。
    @ViewBuilder
    private func ipaInstallControls(latest: String, ipaURL: URL) -> some View {
        switch updateStore.downloadState {
        case .idle:
            primaryButton(icon: "arrow.down.app.fill", title: "下载并安装") {
                updateStore.startDownload(latest: latest, ipaURL: ipaURL)
            }
            Text("App 内下载（自动优先走你的 NAS，不连 GitHub），完成后弹出系统面板交给 TrollStore 安装。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            directJumpControls(latest: latest, ipaURL: ipaURL)

        case .downloading(let received, let total):
            if let total, total > 0 {
                ProgressView(value: Double(received), total: Double(total))
                    .padding(.horizontal, 48)
            } else {
                ProgressView()
            }
            Text("正在下载… \(byteText(received))\(total.map { " / \(byteText($0))" } ?? "")")
                .font(.footnote)
                .foregroundColor(.secondary)
                .monospacedDigit()
            Button("取消下载") { updateStore.cancelDownload() }
                .font(.footnote)
                .foregroundColor(.secondary)

        case .downloaded(let fileURL):
            primaryButton(icon: "arrow.up.forward.app.fill", title: "打开安装面板") {
                openInstallPanel(fileURL)
            }
            Text("在弹出的面板里选择 TrollStore，确认安装即可（同变体会覆盖旧版并保留数据）。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                updateStore.cancelDownload()
                updateStore.startDownload(latest: latest, ipaURL: ipaURL)
            } label: {
                Text("重新下载").font(.footnote).foregroundColor(Theme.brand)
            }

        case .failed(let message):
            primaryButton(icon: "arrow.clockwise", title: "重试下载") {
                updateStore.startDownload(latest: latest, ipaURL: ipaURL)
            }
            Text("下载失败：\(message)")
                .font(.caption2)
                .foregroundColor(.orange)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
            directJumpControls(latest: latest, ipaURL: ipaURL)
        }
    }

    /// 备用路径：不走 App 内下载，直接用 apple-magnifier scheme 唤起 TrollStore。
    /// 在「放大器接管」正常的设备上这是一步直达；接管失败只会打开放大器，
    /// 所以同时自动复制换源后的直链并给出分步引导。
    @ViewBuilder
    private func directJumpControls(latest: String, ipaURL: URL) -> some View {
        HStack(spacing: 24) {
            Button {
                installToTrollStore(ipaURL: ipaURL, version: latest)
            } label: {
                Text("直接唤起 TrollStore")
                    .font(.footnote)
                    .foregroundColor(Theme.brand)
                    .underline()
            }
            Button {
                UIPasteboard.general.string = bestInstallURL(ipaURL, version: latest).absoluteString
                copied = true
                showGuide = true
            } label: {
                Text(copied ? "已复制直链" : "复制直链")
                    .font(.footnote)
                    .foregroundColor(Theme.brand)
            }
        }

        if showGuide || copied {
            VStack(alignment: .leading, spacing: 8) {
                Text("安装链接已复制（已自动换成最快的源）。请按下面步骤完成安装：")
                    .font(.footnote)
                    .foregroundColor(Theme.brand)

                guideStep(1, "打开 TrollStore")
                guideStep(2, "点右上角「+」")
                guideStep(3, "选「从 URL 安装」，粘贴链接")
                guideStep(4, "确认安装（同变体才会覆盖旧版）")

                Text("提示：点「直接唤起」后如果跳到了「放大器」，说明这台设备上 TrollStore 没接管放大器 scheme，用上面的方式粘贴安装即可。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.brand.opacity(0.08))
            .cornerRadius(10)
            .padding(.horizontal, 32)
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

                        // 主路径：App 内下载（自动换源）→ 系统面板交给 TrollStore，
                        // 不再依赖 apple-magnifier scheme 的接管状态。
                        if let ipaURL = ipaURL {
                            ipaInstallControls(latest: latest, ipaURL: ipaURL)
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
            .onChange(of: updateStore.downloadState) { state in
                // 下载完成自动弹出「打开方式」面板，少一次手动点按
                if case .downloaded(let fileURL) = state {
                    openInstallPanel(fileURL)
                }
            }
            .alert("未找到 TrollStore", isPresented: $showNoTrollStoreAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text("面板里没有出现 TrollStore。请确认设备已安装 TrollStore；或用「复制直链」到 TrollStore 里从 URL 安装。")
            }
        }
    }
}

/// UIDocumentInteractionController 的代理宿主（SwiftUI View 是 struct 当不了 NSObject）。
/// 面板的生命周期靠 @State 强引用控制器本身维持，这里无需实现任何回调。
private final class DocControllerHost: NSObject, UIDocumentInteractionControllerDelegate {}
