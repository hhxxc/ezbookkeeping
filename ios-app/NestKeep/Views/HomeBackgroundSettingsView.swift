import SwiftUI
import UIKit

/// 首页背景图设置：上传 / 更换 / 移除汇总卡底图。
/// 走 `POST /api/v1/home/backgrounds/upload.json`（与 Web 的 `uploadHomeBackground` 一致），
/// 该接口在 `EnableTransactionPictures` 开启时注册；未开启时给出明确提示。
struct HomeBackgroundSettingsView: View {
    @Environment(\.mainTabBarInset) private var tabBarInset
    @ObservedObject private var serverSettings = ServerSettings.shared

    @State private var showPicker = false
    @State private var isUploading = false
    @State private var errorText: String?
    @State private var previewURL: URL?
    @State private var showRemoveConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 当前预览
                ZStack {
                    if let url = previewURL {
                        CachedAsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                    } else {
                        placeholder
                    }
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [Theme.brand, Theme.brand.opacity(0.78)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)

                if !serverSettings.enableTransactionPictures {
                    Text("当前服务器未开启图片功能（EnableTransactionPictures），无法设置背景图。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if let errorText = errorText {
                    Text(errorText).font(.footnote).foregroundColor(Theme.expense)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                }

                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 8) {
                        if isUploading { ProgressView().tint(.white) }
                        Image(systemName: "photo.on.rectangle.angled")
                        Text(isUploading ? "上传中…" : (previewURL == nil ? "上传背景图" : "更换背景图")).bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.brand)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isUploading)
                .padding(.horizontal, 16)

                if previewURL != nil {
                    Button(role: .destructive) {
                        showRemoveConfirm = true
                    } label: {
                        Text("移除背景图").frame(maxWidth: .infinity).padding()
                            .background(Theme.expense.opacity(0.12))
                            .foregroundColor(Theme.expense)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 16)
                }

                Text("背景图会作为账单页顶部汇总卡的底图，并自动叠加一层中性压暗蒙层，保证卡片文字清晰可读。")
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.vertical, 16)
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
        .navigationTitle("首页背景图")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await serverSettings.loadIfNeeded()
            previewURL = HomeBackground.imageURL
        }
        .sheet(isPresented: $showPicker) {
            PhotoPicker { data in
                Task { await upload(data) }
            }
        }
        .confirmationDialog("移除背景图？", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("移除", role: .destructive) {
                HomeBackground.remove()
                previewURL = nil
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo").font(.system(size: 30))
            Text("未设置背景图").font(.caption)
        }
        .foregroundColor(.white.opacity(0.9))
    }

    private func upload(_ data: Data) async {
        isUploading = true
        errorText = nil
        do {
            previewURL = try await HomeBackground.upload(imageData: data)
            errorText = nil
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isUploading = false
    }
}
