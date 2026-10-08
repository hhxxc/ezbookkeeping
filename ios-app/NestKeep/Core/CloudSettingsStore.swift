import Foundation
import Combine

/// 云同步应用设置（对齐 Web `stores/setting.ts` 的 `users/settings/cloud/*`）：
///  - `GET  /api/v1/users/settings/cloud/get.json`      → `[ApplicationCloudSetting] | false`
///  - `POST /api/v1/users/settings/cloud/update.json`   → body `{settings:[{settingKey,settingValue}], fullUpdate}`
///  - `POST /api/v1/users/settings/cloud/disable.json`
/// 服务端只接受白名单键（见 Web `ALL_ALLOWED_CLOUD_SYNC_APP_SETTING_KEY_TYPES`）。
@MainActor
final class CloudSettingsStore: ObservableObject {
    static let shared = CloudSettingsStore()

    /// key -> value（字符串形式；布尔/数字也以字符串存）
    @Published private(set) var values: [String: String] = [:]
    @Published private(set) var enabled = false
    @Published private(set) var loaded = false

    /// 允许同步的键（与 Web 白名单一致，只列本 App 用得到的部分）
    static let allowedKeys: Set<String> = [
        "showAccountBalance",
        "autoUpdateExchangeRatesData",
        "showAmountInHomePage",
        "timezoneUsedForStatisticsInHomePage",
        "overviewAccountFilterInHomePage",
        "overviewTransactionCategoryFilterInHomePage",
        "itemsCountInTransactionListPage",
        "showTotalAmountInTransactionListPage",
        "showTagInTransactionListPage",
        "quickSaveButtonStyleInMobileTransactionListPage",
        "quickAddButtonActionInMobileTransactionEditPage",
        "autoSaveTransactionDraft",
        "autoGetCurrentGeoLocation",
        "alwaysShowTransactionPicturesInMobileTransactionEditPage",
        "totalAmountExcludeAccountIds",
        "accountCategoryOrders",
        "hideCategoriesWithoutAccounts",
        "currencySortByInExchangeRatesPage",
        "mapCacheExpiration",
        "exchangeRatesDataCacheExpiration",
        "homeSummaryBackgroundImage",
        "homeGalleryBackgroundId",
        "pageBackgroundImage"
    ]

    func load() async {
        do {
            // 后端可能返回 false（未启用云同步）
            let raw = try await APIClient.shared.requestRaw("/api/v1/users/settings/cloud/get.json")
            if let arr = raw as? [[String: Any]] {
                var dict: [String: String] = [:]
                for item in arr {
                    if let k = item["settingKey"] as? String, let v = item["settingValue"] as? String {
                        dict[k] = v
                    }
                }
                values = dict
                enabled = true
            } else {
                values = [:]
                enabled = false
            }
            loaded = true
        } catch {
            enabled = false
            loaded = true
        }
    }

    /// 读取布尔值（缺省回退默认）
    func bool(_ key: String, default def: Bool) -> Bool {
        guard let raw = values[key] else { return def }
        return raw == "true"
    }

    func int(_ key: String, default def: Int) -> Int {
        guard let raw = values[key] else { return def }
        return Int(raw) ?? def
    }

    func string(_ key: String, default def: String = "") -> String {
        values[key] ?? def
    }

    /// 更新单个设置（非全量）；`value` 为已序列化字符串
    func set(_ key: String, _ value: String) async {
        guard Self.allowedKeys.contains(key) else { return }
        values[key] = value
        do {
            let req = UserCloudSettingsUpdateRequest(
                settings: [CloudSettingItem(settingKey: key, settingValue: value)],
                fullUpdate: false
            )
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/users/settings/cloud/update.json", method: .POST, body: req
            )
        } catch {
            // 静默失败：本地已乐观更新
        }
    }

    /// 停用云同步（不再同步但仍保留本地设置）
    func disable() async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/users/settings/cloud/disable.json", method: .POST
            )
            enabled = false
            values = [:]
        } catch {
            // ignore
        }
    }
}

struct UserCloudSettingsUpdateRequest: Codable {
    let settings: [CloudSettingItem]
    let fullUpdate: Bool
}

struct CloudSettingItem: Codable {
    let settingKey: String
    let settingValue: String
}
