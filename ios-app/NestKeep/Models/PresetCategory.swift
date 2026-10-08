import Foundation

/// 预设分类目录（对齐 Web `src/consts/category.ts` 的 DEFAULT_*_CATEGORIES）。
/// 名称取简体中文（`zh_Hans.json` 的 `category.*` 词条），用于「默认分类」一键导入。
/// type：1=收入 2=支出 3=转账（对应 Go TransactionCategoryType）。
struct PresetCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: Int
    let color: String
    let subCategories: [PresetSubCategory]
}

struct PresetSubCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: Int
    let color: String
}

enum PresetCategoryCatalog {
    /// 全部预设分类，按类型分组
    static func categories(type: Int) -> [PresetCategory] {
        switch type {
        case 1: return incomeCategories
        case 2: return expenseCategories
        case 3: return transferCategories
        default: return []
        }
    }

    static let typeNames: [(Int, String)] = [(1, "收入"), (2, "支出"), (3, "转账")]

    static let incomeCategories: [PresetCategory] = [
        PresetCategory(name: "职业收入", icon: 2000, color: "ff6b22", subCategories: [
            PresetSubCategory(name: "工资收入", icon: 2010, color: "ff6b22"),
            PresetSubCategory(name: "奖金收入", icon: 2020, color: "ff6b22"),
            PresetSubCategory(name: "加班收入", icon: 231, color: "ff6b22"),
            PresetSubCategory(name: "兼职收入", icon: 2080, color: "ff6b22"),
        ]),
        PresetCategory(name: "金融投资", icon: 900, color: "ff9500", subCategories: [
            PresetSubCategory(name: "投资收入", icon: 2100, color: "ff9500"),
            PresetSubCategory(name: "租金收入", icon: 290, color: "ff9500"),
            PresetSubCategory(name: "利息收入", icon: 970, color: "ff9500"),
        ]),
        PresetCategory(name: "其他杂项", icon: 1000, color: "8e8e93", subCategories: [
            PresetSubCategory(name: "礼品红包", icon: 710, color: "8e8e93"),
            PresetSubCategory(name: "中奖收入", icon: 564, color: "8e8e93"),
            PresetSubCategory(name: "意外收入", icon: 5200, color: "8e8e93"),
            PresetSubCategory(name: "其他收入", icon: 3010, color: "8e8e93"),
        ]),
    ]

    static let expenseCategories: [PresetCategory] = [
        PresetCategory(name: "食品饮料", icon: 1, color: "ff6b22", subCategories: [
            PresetSubCategory(name: "食品", icon: 2, color: "ff6b22"),
            PresetSubCategory(name: "饮料", icon: 30, color: "ff6b22"),
            PresetSubCategory(name: "水果零食", icon: 70, color: "ff6b22"),
        ]),
        PresetCategory(name: "服饰外貌", icon: 100, color: "673ab7", subCategories: [
            PresetSubCategory(name: "衣服", icon: 110, color: "673ab7"),
            PresetSubCategory(name: "饰品", icon: 170, color: "673ab7"),
            PresetSubCategory(name: "化妆品", icon: 180, color: "673ab7"),
            PresetSubCategory(name: "美容美发", icon: 190, color: "673ab7"),
        ]),
        PresetCategory(name: "住宅家居", icon: 200, color: "000000", subCategories: [
            PresetSubCategory(name: "家居用品", icon: 210, color: "000000"),
            PresetSubCategory(name: "电子产品", icon: 230, color: "000000"),
            PresetSubCategory(name: "维修保养", icon: 250, color: "000000"),
            PresetSubCategory(name: "家政服务", icon: 260, color: "000000"),
            PresetSubCategory(name: "水电煤气", icon: 270, color: "000000"),
            PresetSubCategory(name: "租金贷款", icon: 290, color: "000000"),
        ]),
        PresetCategory(name: "交通出行", icon: 300, color: "009688", subCategories: [
            PresetSubCategory(name: "公共交通", icon: 310, color: "009688"),
            PresetSubCategory(name: "打车租车", icon: 320, color: "009688"),
            PresetSubCategory(name: "私家车费用", icon: 330, color: "009688"),
            PresetSubCategory(name: "火车票", icon: 370, color: "009688"),
            PresetSubCategory(name: "飞机票", icon: 390, color: "009688"),
        ]),
        PresetCategory(name: "交流通讯", icon: 400, color: "2196f3", subCategories: [
            PresetSubCategory(name: "电话费", icon: 420, color: "2196f3"),
            PresetSubCategory(name: "上网费", icon: 430, color: "2196f3"),
            PresetSubCategory(name: "快递费", icon: 480, color: "2196f3"),
        ]),
        PresetCategory(name: "休闲娱乐", icon: 500, color: "ff2d55", subCategories: [
            PresetSubCategory(name: "运动健身", icon: 510, color: "ff2d55"),
            PresetSubCategory(name: "聚会支出", icon: 540, color: "ff2d55"),
            PresetSubCategory(name: "电影演出", icon: 550, color: "ff2d55"),
            PresetSubCategory(name: "玩具游戏", icon: 560, color: "ff2d55"),
            PresetSubCategory(name: "会员订阅", icon: 570, color: "ff2d55"),
            PresetSubCategory(name: "宠物花费", icon: 580, color: "ff2d55"),
            PresetSubCategory(name: "旅游度假", icon: 590, color: "ff2d55"),
        ]),
        PresetCategory(name: "教育学习", icon: 600, color: "cddc39", subCategories: [
            PresetSubCategory(name: "书报杂志", icon: 610, color: "cddc39"),
            PresetSubCategory(name: "培训课程", icon: 660, color: "cddc39"),
            PresetSubCategory(name: "认证考试", icon: 680, color: "cddc39"),
        ]),
        PresetCategory(name: "礼物捐赠", icon: 700, color: "4cd964", subCategories: [
            PresetSubCategory(name: "礼物", icon: 710, color: "4cd964"),
            PresetSubCategory(name: "捐赠", icon: 780, color: "4cd964"),
        ]),
        PresetCategory(name: "医疗健康", icon: 800, color: "ff3b30", subCategories: [
            PresetSubCategory(name: "检查治疗", icon: 840, color: "ff3b30"),
            PresetSubCategory(name: "药品", icon: 860, color: "ff3b30"),
            PresetSubCategory(name: "医疗器械", icon: 890, color: "ff3b30"),
        ]),
        PresetCategory(name: "金融保险", icon: 900, color: "ff9500", subCategories: [
            PresetSubCategory(name: "税费支出", icon: 910, color: "ff9500"),
            PresetSubCategory(name: "手续费", icon: 930, color: "ff9500"),
            PresetSubCategory(name: "保险支出", icon: 950, color: "ff9500"),
            PresetSubCategory(name: "利息支出", icon: 970, color: "ff9500"),
            PresetSubCategory(name: "赔偿罚款", icon: 990, color: "ff9500"),
        ]),
        PresetCategory(name: "其他杂项", icon: 1000, color: "8e8e93", subCategories: [
            PresetSubCategory(name: "其他支出", icon: 1010, color: "8e8e93"),
        ]),
    ]

    static let transferCategories: [PresetCategory] = [
        PresetCategory(name: "一般转账", icon: 4000, color: "ff6b22", subCategories: [
            PresetSubCategory(name: "银行转账", icon: 900, color: "ff6b22"),
            PresetSubCategory(name: "信用卡还款", icon: 980, color: "ff6b22"),
            PresetSubCategory(name: "存款取款", icon: 981, color: "ff6b22"),
        ]),
        PresetCategory(name: "贷款债务", icon: 950, color: "ff9500", subCategories: [
            PresetSubCategory(name: "借入", icon: 910, color: "ff9500"),
            PresetSubCategory(name: "借出", icon: 290, color: "ff9500"),
            PresetSubCategory(name: "还款", icon: 930, color: "ff9500"),
            PresetSubCategory(name: "收债", icon: 5030, color: "ff9500"),
        ]),
        PresetCategory(name: "其他杂项", icon: 1000, color: "8e8e93", subCategories: [
            PresetSubCategory(name: "垫付支出", icon: 2010, color: "8e8e93"),
            PresetSubCategory(name: "报销", icon: 920, color: "8e8e93"),
            PresetSubCategory(name: "其他转账", icon: 4900, color: "8e8e93"),
        ]),
    ]

}
