import Foundation
import UIKit

/// 交易图片上传（multipart/form-data，字段名 `picture`）。
/// 后端 `TransactionPictureUploadHandler` 要求表单字段为 `picture`，
/// 返回 `{ pictureId, originalUrl }`（pictureId 为字符串化 int64）。
enum PictureUploader {

    struct UploadedPicture: Codable {
        let pictureId: String
        let originalUrl: String
    }

    /// 上传一张图片，返回 pictureId（失败抛 APIError）
    /// - Parameters:
    ///   - path: 上传接口路径；默认交易图片接口。首页背景图用 `/api/v1/home/backgrounds/upload.json`
    ///   - fieldName: multipart 表单字段名；默认 `picture`（两个接口都用这个名字）
    static func upload(
        imageData: Data,
        fileName: String = "photo.jpg",
        path: String = "/api/v1/transaction/pictures/upload.json",
        fieldName: String = "picture"
    ) async throws -> UploadedPicture {
        let boundary = "----NestKeepBoundary\(UUID().uuidString)"
        guard let components = URLComponents(
            url: AppSettings.shared.serverURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ), let url = components.url else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = AuthManager.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let tz = TimeZone.current
        req.setValue("\(tz.secondsFromGMT() / 60)", forHTTPHeaderField: "X-Timezone-Offset")
        req.setValue(tz.identifier, forHTTPHeaderField: "X-Timezone-Name")

        var body = Data()
        let ext = (fileName as NSString).pathExtension.lowercased()
        let contentType = ext == "png" ? "image/png" : "image/jpeg"

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: req)
        let decoder = JSONDecoder()
        // 交易图片返回 { pictureId, originalUrl }；首页背景图只返回 { url }，统一容错
        if let envelope = try? decoder.decode(APIEnvelope<UploadedPicture>.self, from: data) {
            if envelope.success, let result = envelope.result { return result }
            throw APIError.server(code: envelope.errorCode ?? -1,
                                  message: envelope.errorMessage ?? "图片上传失败")
        }
        if let envelope = try? decoder.decode(APIEnvelope<UploadedPictureURL>.self, from: data) {
            if envelope.success, let result = envelope.result {
                return UploadedPicture(pictureId: "", originalUrl: result.url)
            }
            throw APIError.server(code: envelope.errorCode ?? -1,
                                  message: envelope.errorMessage ?? "图片上传失败")
        }
        throw APIError.invalidResponse
    }
}

/// 首页背景图上传的返回体 `{ "url": "..." }`
struct UploadedPictureURL: Codable {
    let url: String
}

// MARK: - 用户头像

/// 用户头像：上传 / 移除 / 展示 URL 构建。
///
/// 后端接口（`avatar_provider = internal` 时启用，见 conf/ezbookkeeping.ini）：
///   POST /api/v1/users/avatar/update.json   multipart 字段 `avatar` → 完整 UserProfileResponse
///   POST /api/v1/users/avatar/remove.json                     → 完整 UserProfileResponse
///   GET  {root}avatar/{uid}.{ext}                            → 图片本体（query token 鉴权）
///
/// 后端返回的 avatar 字符串按服务器 root_url 拼接（本容器默认 root_url 是
/// `http://localhost:15080/`，对外是无效 host），因此展示时**一律取 `avatar/…`
/// 后缀按当前登录服务器地址重拼**，不信任返回值里的 host 部分。
enum AvatarUploader {

    private static let versionKey = "nestkeep.avatarVersion"

    /// 压缩上限：服务端 max_user_avatar_size = 1MB，512px JPEG 远低于上限且头像足够清晰
    private static let maxUploadDimension: CGFloat = 512

    /// 选图结果压缩成可上传的 JPEG（≤512px）
    static func prepareData(_ image: UIImage) -> Data? {
        let resized = resizedImage(image, maxDimension: maxUploadDimension)
        return resized.jpegData(compressionQuality: 0.85)
    }

    /// 上传/更换头像，成功后返回更新后的用户信息（同时提升缓存版本号）
    @discardableResult
    static func upload(imageData: Data, fileName: String = "avatar.jpg") async throws -> UserBasicInfo {
        let result = try await multipartUpload(
            imageData: imageData,
            fileName: fileName,
            path: "/api/v1/users/avatar/update.json",
            fieldName: "avatar"
        )
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(APIEnvelope<UserProfileResponse>.self, from: result) {
            if envelope.success, let profile = envelope.result {
                bumpVersion()
                return profile.asBasicInfo
            }
            throw APIError.server(code: envelope.errorCode ?? -1,
                                  message: envelope.errorMessage ?? "头像上传失败")
        }
        throw APIError.invalidResponse
    }

    /// 移除头像，成功后返回更新后的用户信息
    @discardableResult
    static func remove() async throws -> UserBasicInfo {
        let resp: UserProfileResponse = try await APIClient.shared.request(
            "/api/v1/users/avatar/remove.json", method: .POST
        )
        bumpVersion()
        return resp.asBasicInfo
    }

    /// 展示用 URL：带 token 与缓存版本号（上传/移除时提升版本，强制列表刷新）。
    /// 无头像或未登录时返回 nil。
    static func displayURL(for avatar: String?) -> URL? {
        guard let avatar = avatar?.trimmingCharacters(in: .whitespacesAndNewlines),
              !avatar.isEmpty,
              let token = AuthManager.shared.token else {
            return nil
        }

        // 取 avatar/ 后缀重拼，规避 root_url 指向 localhost 等无效 host
        let suffix: String
        if let range = avatar.range(of: "avatar/") {
            suffix = String(avatar[range.lowerBound...])
        } else if avatar.hasPrefix("http") {
            return nil
        } else {
            suffix = avatar
        }

        guard var comp = URLComponents(
            url: AppSettings.shared.serverURL.appendingPathComponent(suffix),
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }

        var items = [URLQueryItem(name: "token", value: token)]
        let version = UserDefaults.standard.integer(forKey: versionKey)
        if version > 0 {
            items.append(URLQueryItem(name: "_v", value: String(version)))
        }
        comp.queryItems = items
        return comp.url
    }

    private static func bumpVersion() {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: versionKey) + 1, forKey: versionKey)
    }

    /// 等比缩小到最长边不超过 maxDimension（UIImage.draw 按 orientation 正确绘制）
    private static func resizedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > maxDimension, maxSide > 0 else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// multipart/form-data 上传（与 PictureUploader 同构，但返回原始 result 数据由调用方解码）
    private static func multipartUpload(
        imageData: Data,
        fileName: String,
        path: String,
        fieldName: String
    ) async throws -> Data {
        let boundary = "----NestKeepBoundary\(UUID().uuidString)"
        guard let components = URLComponents(
            url: AppSettings.shared.serverURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ), let url = components.url else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = AuthManager.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let tz = TimeZone.current
        req.setValue("\(tz.secondsFromGMT() / 60)", forHTTPHeaderField: "X-Timezone-Offset")
        req.setValue(tz.identifier, forHTTPHeaderField: "X-Timezone-Name")

        let ext = (fileName as NSString).pathExtension.lowercased()
        let contentType = ext == "png" ? "image/png" : "image/jpeg"

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }
}
