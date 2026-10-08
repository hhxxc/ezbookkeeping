import Foundation

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

    /// 上传背景图，成功则写入本地并返回可展示的 URL
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
        return imageURL(for: relative)
    }

    static func remove() {
        path = ""
    }
}

extension Notification.Name {
    /// 首页背景图变化（首页据此刷新汇总卡底图）
    static let homeBackgroundChanged = Notification.Name("nestkeep.homeBackgroundChanged")
}
