import Foundation

/// 分类类型（对应 Go TransactionCategoryType）
enum TransactionCategoryType: Int, Codable, Hashable {
    case income = 1
    case expense = 2
    case transfer = 3
}

/// 交易分类（对应 Go TransactionCategoryInfoResponse）
struct TransactionCategory: Codable, Identifiable {
    let id: String
    let name: String
    let parentId: String?
    let type: Int?
    let icon: String?
    let color: String?
    let comment: String?
    let displayOrder: Int?
    let hidden: Bool?
    let subCategories: [TransactionCategory]?
}

/// 分类列表接口的响应包装。
/// 后端 `/api/v1/transaction/categories/list.json` 返回**按类型分组的字典**
/// （如 `{"1":[...收入分类...],"2":[...支出分类...]}`，与 Web 端
/// `Record<number, TransactionCategoryInfoResponse[]>` 的契约一致），
/// 原生端此前按数组解码必然失败，导致首页 load() 中断、数据全 0。
/// 这里统一解码并拍平成数组；同时兼容直接返回数组的情况。
struct TransactionCategoryList: Decodable {
    let categories: [TransactionCategory]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: [TransactionCategory]].self) {
            // 字典键是类型数字字符串（"1"/"2"/"3"），按键排序保证收入在前、支出在后
            categories = dict.keys.sorted().flatMap { dict[$0] ?? [] }
        } else if let arr = try? container.decode([TransactionCategory].self) {
            categories = arr
        } else {
            categories = []
        }
    }
}
