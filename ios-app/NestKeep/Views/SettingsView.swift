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
                }

                // 版本与更新
                Section(header: Text("关于")) {
                    HStack {
                        Text("App 版本")
                        Spacer()
                        Text("\(UpdateChecker.currentAppVersion) (\(UpdateChecker.currentBuildNumber))")
                            .foregroundColor(.secondary)
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
            .navigationTitle("我的")
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

                        // 主按钮：复制 IPA 直链（TrollStore「从 URL 安装」用）
                        if let ipaURL = ipaURL {
                            Button {
                                UIPasteboard.general.string = ipaURL.absoluteString
                                copied = true
                            } label: {
                                HStack {
                                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                                    Text(copied ? "已复制，去 TrollStore 粘贴安装" : "复制 IPA 直链").bold()
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Theme.brand)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .padding(.horizontal, 32)
                            Text("TrollStore → 右上角 + → 从 URL 安装，粘贴即装。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
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
                if !checking { copied = false }
            }
        }
    }
}
