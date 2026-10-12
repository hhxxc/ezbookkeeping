import Foundation
import SwiftUI

/// 首页汇总卡背景图。
///
/// 上传：`POST /api/v1/home/backgrounds/upload.json`（multipart，字段名 `picture`），
/// 返回 `{ "url": "<相对路径>" }`，与 Web 端 `uploadHomeBackground` 完全一致。
/// 读取：后端返回的是**相对路径**（如 `home/background/xxx.jpg`），
/// 展示时需拼上服务器地址并带 `?token=`（该图片接口按 token 鉴权，与交易图片同款）。
///
/// 本地只存相对路径（UserDefaults），换服务器无需重传。
enum HomeBackground {
    private static let key = "nestkeep.homeBackgroundPath"

    /// 服务端返回的相对路径（空串表示未设置）
    static var path: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: .homeBackgroundChanged, object: nil)
        }
    }

    static var isSet: Bool { !path.isEmpty }

    /// 可直接用于 AsyncImage 的完整 URL（带 token；无 token 时返回 nil）
    static var imageURL: URL? {
        imageURL(for: path)
    }

    /// 指定相对路径 → 完整 URL
    static func imageURL(for relativePath: String) -> URL? {
        guard !relativePath.isEmpty else { return nil }
        // 兼容历史 base64（旧版 Web 曾把图直接存成 data URL）
        if relativePath.hasPrefix("data:") { return URL(string: relativePath) }
        guard let token = AuthManager.shared.token,
              var comp = URLComponents(
                url: AppSettings.shared.serverURL.appendingPathComponent(relativePath),
                resolvingAgainstBaseURL: false
              ) else {
            return nil
        }
        comp.queryItems = [URLQueryItem(name: "token", value: token)]
        return comp.url
    }

    /// 上传背景图，成功则写入本地+云端并返回可展示的 URL。
    /// 云设置 `homeSummaryBackgroundImage` 与 Web 端共用：Web 上传的背景图原生也能读到。
    static func upload(imageData: Data, fileName: String = "background.jpg") async throws -> URL? {
        let res = try await PictureUploader.upload(
            imageData: imageData,
            fileName: fileName,
            path: "/api/v1/home/backgrounds/upload.json",
            fieldName: "picture"
        )
        // 该接口返回 { url }，PictureUploader 复用 originalUrl 字段承载
        let relative = res.originalUrl
        path = relative
        await CloudSettingsStore.shared.set("homeSummaryBackgroundImage", relative)
        return imageURL(for: relative)
    }

    static func remove() {
        path = ""
        presetID = ""
        Task {
            await CloudSettingsStore.shared.set("homeSummaryBackgroundImage", "")
        }
    }

    /// 从云端用户设置拉取背景图（云端优先）。
    /// Web 端上传的背景图存在 `homeSummaryBackgroundImage` 云设置里，原生登录后拉一次即可共用；
    /// 云同步未启用时保持本地值不动。
    @MainActor
    static func syncFromCloud() async {
        let store = CloudSettingsStore.shared
        if !store.loaded {
            await store.load()
        }
        guard store.enabled else { return }
        let cloud = store.string("homeSummaryBackgroundImage")
        if cloud != path {
            if cloud.isEmpty && !path.isEmpty {
                // 旧版本原生上传的背景图还没写进云端：把本地值推上去，避免被云端清空
                await store.set("homeSummaryBackgroundImage", path)
            } else {
                path = cloud
            }
        }
    }
}

extension Notification.Name {
    /// 首页背景图变化（首页据此刷新汇总卡底图）
    static let homeBackgroundChanged = Notification.Name("nestkeep.homeBackgroundChanged")
}

// MARK: - 内置默认背景（必应壁纸精选风景，按卡片比例裁剪的小尺寸高清图）

/// 单个预设：风景图走 imageName（Assets 里的 BGPresets）；colors 渐变仅作图片缺失时的兜底
struct PresetBackground: Identifiable {
    let id: String
    let name: String
    let imageName: String
    let colors: [Color]
}

/// 背景来源：无 / 内置预设 / 服务器图片
enum HomeBackgroundSource {
    case none
    case preset(PresetBackground)
    case remote(URL)

    var isNone: Bool {
        if case .none = self { return true }
        return false
    }
}

extension HomeBackground {
    static let presets: [PresetBackground] = [
        PresetBackground(id: "danxia",   name: "丹霞",     imageName: "bg-danxia",
                         colors: [Color(hex: "#E07C3E"), Color(hex: "#8A4A2B")]),
        PresetBackground(id: "yosemite", name: "优山美地", imageName: "bg-yosemite",
                         colors: [Color(hex: "#F2A06B"), Color(hex: "#8A6A55")]),
        PresetBackground(id: "seaside",  name: "海岸栈桥", imageName: "bg-seaside",
                         colors: [Color(hex: "#5B87A6"), Color(hex: "#2E4A62")]),
        PresetBackground(id: "autumn",   name: "秋日磨坊", imageName: "bg-autumn",
                         colors: [Color(hex: "#D98E32"), Color(hex: "#7A4A21")]),
        PresetBackground(id: "corsica",  name: "科西嘉",   imageName: "bg-corsica",
                         colors: [Color(hex: "#D99A4E"), Color(hex: "#3E6E8E")]),
        PresetBackground(id: "river",    name: "冰川河",   imageName: "bg-river",
                         colors: [Color(hex: "#3FA8C9"), Color(hex: "#9A7A2E")]),
    ]

    private static let presetKey = "nestkeep.homeBackgroundPreset"

    /// 选中的内置预设 id（空串 = 未选；预设是本地资产，不上云）
    static var presetID: String {
        get { UserDefaults.standard.string(forKey: presetKey) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: presetKey)
            NotificationCenter.default.post(name: .homeBackgroundChanged, object: nil)
        }
    }

    static func preset(byID id: String) -> PresetBackground? {
        presets.first { $0.id == id }
    }

    /// 当前生效的背景来源：预设优先于远端图
    static var source: HomeBackgroundSource {
        if !presetID.isEmpty, let p = preset(byID: presetID) { return .preset(p) }
        if let url = imageURL { return .remote(url) }
        return .none
    }

    /// 选择内置预设（本地切换；远端图路径与云端设置一并清空，避免下拉刷新被远端图盖回）
    static func selectPreset(_ id: String) {
        presetID = id
        if !path.isEmpty {
            path = ""
        }
        Task {
            await CloudSettingsStore.shared.set("homeSummaryBackgroundImage", "")
        }
    }
}

/// 内置预设背景渲染：优先用打包的风景图（resizable 填充，高清条幅按卡片裁切显示）；
/// 图片缺失时退回对角渐变 + 半透明装饰
struct PresetBackgroundView: View {
    let preset: PresetBackground

    var body: some View {
        if let ui = UIImage(named: preset.imageName) {
            // 硬约束到容器尺寸再铺满裁切：scaledToFill 若不加限，会把父容器布局宽度
            // 撑大到图片自然尺寸（sheet 内容整体左右超出屏幕的根因），GeometryReader
            // 把图钉死在提案尺寸内，视觉铺满、布局零溢出
            GeometryReader { geo in
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    // 轻蒙层：比远端图（0.28）轻，风景观感优先，只兜底白字可读性
                    .overlay(Color.black.opacity(0.15))
            }
        } else {
            gradientFallback
        }
    }

    private var gradientFallback: some View {
        ZStack {
            LinearGradient(colors: preset.colors,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: w * 0.9, height: w * 0.9)
                    .offset(x: -w * 0.35, y: -h * 0.9)
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: w * 0.7, height: w * 0.7)
                    .offset(x: w * 0.55, y: h * 0.35)
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1.5)
                    .frame(width: w * 0.32, height: w * 0.32)
                    .offset(x: w * 0.10, y: h * 0.55)
            }
        }
    }
}
