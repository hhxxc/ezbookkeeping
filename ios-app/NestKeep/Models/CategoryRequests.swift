import Foundation

// MARK: - 分类写操作请求体（对应 Go TransactionCategory*Request）

/// 新增分类
struct CategoryCreateRequest: Codable {
    let name: String
    let type: Int
    let parentId: String
    let icon: String
    let color: String
    let comment: String
    let clientSessionId: String

    init(name: String, type: Int, parentId: String = "0", icon: String,
         color: String, comment: String = "") {
        self.name = name
        self.type = type
        self.parentId = parentId
        self.icon = icon
        self.color = color
        self.comment = comment
        self.clientSessionId = UUID().uuidString
    }
}

/// 修改分类
struct CategoryModifyRequest: Codable {
    let id: String
    let name: String
    let parentId: String
    let icon: String
    let color: String
    let comment: String
    let hidden: Bool
}

/// 分类删除 / 显隐
struct CategoryIdRequest: Codable { let id: String }
struct CategoryHideRequest: Codable { let id: String; let hidden: Bool }

/// 分类排序（`POST /api/v1/transaction/categories/move.json`）
struct CategoryMoveRequest: Codable {
    let newDisplayOrders: [CategoryNewDisplayOrderRequest]
}
struct CategoryNewDisplayOrderRequest: Codable {
    let id: String
    let displayOrder: Int
}

/// 分类图标映射（后端 icon 为图标字体编号，与 Web `src/consts/icon.ts` ALL_CATEGORY_ICONS 同一编号体系：
/// 1~99 餐饮、100~199 服饰、200~299 家居、300~399 交通、400~499 通讯、500~599 娱乐、
/// 600~699 教育、700~799 礼品捐赠、800~899 医疗、900~999 金融保险、1000+ 杂项、
/// 2000+ 收入、4000 转账、6000+ 品牌。SF Symbols 取 iOS 15 可用的近似图形）。
enum CategoryIconCatalog {
    /// 全量编号 -> SF Symbol（未知编号回退 "tag"）
    private static let map: [Int: String] = [
        // 餐饮（注意：SF Symbol 名必须 iOS 15.1 可用，bell.concierge/wineglass/cake 等新版名在用户机上渲染空白）
        1: "fork.knife", 2: "fork.knife", 10: "takeoutbag.and.cup.and.straw",
        11: "fork.knife.circle", 12: "takeoutbag.and.cup.and.straw", 13: "takeoutbag.and.cup.and.straw",
        30: "cup.and.saucer.fill", 31: "cup.and.saucer", 32: "cup.and.saucer",
        40: "cup.and.saucer.fill", 41: "cup.and.saucer.fill", 42: "cup.and.saucer.fill", 43: "cup.and.saucer.fill", 44: "cup.and.saucer.fill",
        60: "leaf.fill", 61: "leaf", 70: "snowflake", 71: "takeoutbag.and.cup.and.straw", 72: "sparkles",
        // 服饰
        100: "person.crop.square", 110: "tshirt", 130: "tshirt", 140: "tshirt", 150: "tshirt",
        170: "diamond", 171: "diamond.fill", 180: "paintbrush", 190: "scissors",
        // 家居（SF3.1 前无 couch/chair/bathtub/toilet，用近似家具图形）
        200: "house", 201: "bag.fill", 202: "building.2", 210: "scroll", 211: "umbrella",
        212: "face.smiling", 220: "house.fill", 221: "bed.double", 222: "bed.double", 223: "drop.fill", 224: "drop",
        230: "cpu", 231: "lightbulb", 232: "wind", 240: "camera", 241: "printer",
        250: "wrench.and.screwdriver", 251: "wrench", 252: "wrench.fill", 253: "paintbrush",
        260: "sparkles", 270: "drop", 271: "flame", 290: "doc.plaintext",
        // 交通
        300: "exclamationmark.triangle.fill", 310: "bus", 311: "tram", 320: "car.fill",
        330: "car", 331: "car.2", 332: "car.2.fill", 333: "car.2",
        340: "bolt.car", 341: "fuelpump", 342: "drop.fill", 343: "bolt.fill",
        350: "bicycle", 351: "bicycle", 370: "tram.fill", 380: "ferry", 390: "airplane", 391: "airplane",
        // 通讯
        400: "phone.fill", 410: "printer", 420: "iphone", 421: "ipad.landscape",
        430: "desktopcomputer", 431: "laptopcomputer", 440: "wifi",
        441: "antenna.radiowaves.left.and.right", 442: "antenna.radiowaves.left.and.right",
        443: "arrow.left.arrow.right", 450: "tv", 451: "antenna.radiowaves.left.and.right",
        460: "envelope", 470: "shippingbox", 471: "shippingbox.fill", 480: "shippingbox", 490: "globe",
        // 娱乐
        500: "heart", 510: "sportscourt", 511: "figure.walk", 512: "figure.walk",
        513: "figure.walk", 514: "bicycle", 515: "figure.walk", 516: "snowflake",
        517: "snowflake", 518: "figure.walk", 519: "location.north.circle",
        520: "sportscourt", 521: "sportscourt.fill", 522: "sportscourt.fill", 523: "sportscourt.fill", 524: "sportscourt.fill",
        530: "sportscourt", 531: "sportscourt", 532: "sportscourt",
        540: "mic.fill", 541: "music.note", 542: "music.note",
        550: "film", 551: "record.circle", 552: "video", 553: "music.note", 554: "headphones", 555: "eyeglasses",
        560: "gamecontroller", 561: "puzzlepiece.fill", 562: "puzzlepiece", 563: "dice.fill", 564: "dice", 565: "crown",
        570: "person.text.rectangle", 571: "waveform",
        580: "pawprint.fill", 581: "drop.fill", 582: "hare", 583: "pawprint", 589: "pawprint.fill",
        590: "umbrella.fill", 591: "drop.fill", 592: "shippingbox", 593: "drop.fill",
        594: "building.columns", 595: "sun.max.fill", 596: "map", 597: "bed.double", 599: "globe",
        // 教育
        600: "text.book.closed", 610: "book", 611: "book.fill", 620: "newspaper",
        640: "graduationcap", 660: "person.2", 680: "star.circle",
        // 礼品捐赠
        700: "gift", 710: "gift", 711: "gift.fill", 720: "gift", 760: "heart.fill", 780: "hand.thumbsup",
        // 医疗
        800: "cross.case", 810: "cross.case.fill", 811: "cross.case.fill",
        820: "person.crop.circle.badge.checkmark", 821: "stethoscope", 840: "stethoscope",
        850: "cross.case.fill", 860: "pills", 861: "pills", 862: "pills", 863: "bandage",
        870: "waveform.path.ecg", 880: "eyeglasses", 881: "figure.walk", 890: "thermometer",
        891: "cross.case.fill", 892: "message", 893: "pills",
        // 金融保险（支出侧）
        900: "building.columns", 910: "dollarsign.circle", 920: "doc.text", 930: "banknote",
        950: "doc.text.fill", 960: "checkmark.square", 970: "percent", 980: "creditcard",
        981: "banknote.fill", 990: "exclamationmark.circle.fill",
        // 杂项（支出侧）
        1000: "pencil", 1010: "minus.circle", 1020: "curlybraces",
        1021: "chevron.left.forwardslash.chevron.right", 1022: "server.rack", 1023: "internaldrive",
        1024: "memorychip", 1025: "cpu", 1026: "hare", 1027: "link", 1100: "leaf.fill",
        // 收入
        2000: "suitcase", 2010: "wallet.pass", 2020: "crown.fill", 2021: "star.circle",
        2080: "person.crop.circle.badge.clock",
        2100: "chart.bar", 2101: "chart.line.uptrend.xyaxis",
        3010: "plus.circle", 3100: "arrow.triangle.2.circlepath",
        4000: "arrow.left.arrow.right", 4900: "arrow.right.circle",
        5000: "star", 5010: "wand.and.stars", 5020: "infinity", 5030: "list.bullet.rectangle",
        5040: "trash", 5050: "scalemass",
        5100: "bag", 5101: "bag.fill", 5102: "cart", 5200: "banknote",
        // 品牌
        6000: "cart.fill", 6001: "globe", 6010: "message.fill",
        6100: "app.badge", 6101: "play", 6200: "pc", 6300: "lightbulb.fill",
        6400: "car.fill", 6410: "house.fill",
        6500: "shippingbox", 6501: "shippingbox.fill", 6502: "shippingbox", 6503: "shippingbox.fill",
        7000: "gamecontroller.fill", 7001: "gamecontroller.fill", 7100: "gamecontroller.fill",
        7200: "play.tv", 7300: "music.note.list", 7301: "music.note",
        8000: "note.text", 8100: "paintbrush.pointed",
        9000: "icloud", 9001: "server.rack", 9002: "drop",
        9100: "chevron.left.forwardslash.chevron.right", 9101: "curlybraces"
    ]

    /// 新建/编辑分类时的可选图标（真实编号，对齐 Web 语义）
    static let options: [(Int, String)] = [
        (1, "fork.knife"), (10, "takeoutbag.and.cup.and.straw"), (31, "cup.and.saucer"), (40, "cup.and.saucer.fill"),
        (60, "leaf.fill"), (110, "tshirt"), (170, "diamond"), (190, "scissors"),
        (200, "house"), (220, "house.fill"), (221, "bed.double"), (230, "cpu"), (231, "lightbulb"),
        (240, "camera"), (250, "wrench.and.screwdriver"), (270, "drop"), (271, "flame"),
        (310, "bus"), (330, "car"), (340, "bolt.car"), (341, "fuelpump"),
        (350, "bicycle"), (370, "tram"), (380, "ferry"), (390, "airplane"),
        (400, "phone.fill"), (420, "iphone"), (431, "laptopcomputer"),
        (440, "wifi"), (450, "tv"), (460, "envelope"), (490, "globe"),
        (500, "heart"), (510, "sportscourt"), (520, "sportscourt"), (540, "mic.fill"),
        (550, "film"), (553, "music.note"), (554, "headphones"), (560, "gamecontroller"),
        (561, "puzzlepiece.fill"), (562, "puzzlepiece"), (563, "dice.fill"), (565, "crown"),
        (580, "pawprint.fill"), (581, "drop.fill"), (583, "pawprint"), (594, "building.columns"),
        (595, "sun.max.fill"), (596, "map"),
        (600, "text.book.closed"), (611, "book.fill"), (620, "newspaper"), (640, "graduationcap"),
        (680, "star.circle"), (700, "gift"), (710, "gift"), (720, "gift"),
        (760, "heart.fill"), (800, "cross.case"), (840, "stethoscope"), (850, "cross.case.fill"),
        (861, "pills"), (863, "bandage"), (880, "eyeglasses"), (890, "thermometer"),
        (900, "building.columns"), (910, "dollarsign.circle"), (920, "doc.text"), (930, "banknote"),
        (960, "checkmark.square"), (970, "percent"), (980, "creditcard"),
        (1000, "pencil"), (1020, "curlybraces"), (1021, "chevron.left.forwardslash.chevron.right"),
        (1022, "server.rack"), (1025, "cpu"), (1027, "link"), (1100, "leaf.fill"),
        (2000, "suitcase"), (2010, "wallet.pass"), (2020, "crown.fill"),
        (2080, "person.crop.circle.badge.clock"), (2100, "chart.bar"), (2101, "chart.line.uptrend.xyaxis"),
        (3010, "plus.circle"), (3100, "arrow.triangle.2.circlepath"),
        (4000, "arrow.left.arrow.right"), (4900, "arrow.right.circle"),
        (5000, "star"), (5010, "wand.and.stars"), (5020, "infinity"), (5040, "trash"),
        (5100, "bag"), (5101, "bag.fill"), (5102, "cart"), (5200, "banknote")
    ]

    static func symbol(_ icon: String?) -> String {
        guard let n = Int(icon ?? "") else { return "tag" }
        return map[n] ?? "tag"
    }
}
