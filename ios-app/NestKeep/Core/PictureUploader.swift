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
    static func upload(imageData: Data, fileName: String = "photo.jpg") async throws -> UploadedPicture {
        let boundary = "----NestKeepBoundary\(UUID().uuidString)"
        guard var components = URLComponents(
            url: AppSettings.shared.serverURL.appendingPathComponent("/api/v1/transaction/pictures/upload.json"),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidURL }
        guard let url = components.url else { throw APIError.invalidURL }

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
        body.append("Content-Disposition: form-data; name=\"picture\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: req)
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(APIEnvelope<UploadedPicture>.self, from: data) else {
            throw APIError.invalidResponse
        }
        if envelope.success, let result = envelope.result {
            return result
        }
        throw APIError.server(code: envelope.errorCode ?? -1, message: envelope.errorMessage ?? "图片上传失败")
    }
}
