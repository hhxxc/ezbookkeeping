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
