import SwiftUI
import UIKit

/// 首页背景图设置：内置默认背景（本地渐变预设）/ 上传自定义图 / 移除。
/// 自定义图走 `POST /api/v1/home/backgrounds/upload.json`（与 Web 的 `uploadHomeBackground` 一致），
/// 该接口在 `EnableTransactionPictures` 开启时注册；未开启时给出明确提示（预设不受影响）。
struct HomeBackgroundSettingsView: View {
    @Environment(\.mainTabBarInset) private var tabBarInset
    @ObservedObject private var serverSettings = ServerSettings.shared

    @State private var showPicker = false
    @State private var isUploading = false
    @State private var errorText: String?
    @State private var showRemoveConfirm = false
    /// 背景变化时递增驱动预览区重绘（来源直接读 HomeBackground.source）
    @State private var refreshToken = UUID()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 当前预览
                ZStack {
                    switch HomeBackground.source {
                    case .remote(let url):
                        CachedAsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView().tint(.white)
                        }
                    case .preset(let preset):
                        PresetBackgroundView(preset: preset)
                    case .none:
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

                // 内置默认背景：本地渐变预设，点选即用（小体积、任意尺寸清晰）
                VStack(alignment: .leading, spacing: 10) {
                    Text("默认背景")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(HomePalette.ink)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                        GridItem(.flexible(), spacing: 10),
                                        GridItem(.flexible(), spacing: 10)],
                              spacing: 10) {
                        ForEach(HomeBackground.presets) { preset in
                            presetCell(preset)
                        }
                    }
                }
                .padding(.horizontal, 16)

                if !serverSettings.enableTransactionPictures {
                    Text("当前服务器未开启图片功能（EnableTransactionPictures），无法上传自定义背景图。")
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
                        Text(isUploading ? "上传中…" : "上传自定义背景图").bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.brand)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isUploading)
                .padding(.horizontal, 16)

                if !HomeBackground.source.isNone {
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

                Text("默认背景由本地绘制、任意尺寸都清晰；自定义背景图会作为汇总卡底图并自动叠加一层中性压暗蒙层，保证文字清晰可读。")
                    .font(.footnote).foregroundColor(.secondary)
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
            refreshToken = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeBackgroundChanged)) { _ in
            refreshToken = UUID()
        }
        .sheet(isPresented: $showPicker) {
            PhotoPicker { data in
                Task { await upload(data) }
            }
        }
        .confirmationDialog("移除背景图？", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("移除", role: .destructive) {
                HomeBackground.remove()
                refreshToken = UUID()
            }
            Button("取消", role: .cancel) {}
        }
    }

    /// 预设格：迷你渐变预览 + 名称 + 选中角标
    private func presetCell(_ preset: PresetBackground) -> some View {
        let selected = HomeBackground.presetID == preset.id
        return Button {
            HomeBackground.selectPreset(preset.id)
            refreshToken = UUID()
        } label: {
            ZStack(alignment: .bottom) {
                PresetBackgroundView(preset: preset)
                    .frame(height: 64)
                Text(preset.name)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.bottom, 5)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(5)
                }
            }
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Theme.brand : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo").font(.system(size: 30))
            Text("未设置背景图").font(.footnote)
        }
        .foregroundColor(.white.opacity(0.9))
    }

    private func upload(_ data: Data) async {
        isUploading = true
        errorText = nil
        do {
            _ = try await HomeBackground.upload(imageData: data)
            errorText = nil
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isUploading = false
        refreshToken = UUID()
    }
}
