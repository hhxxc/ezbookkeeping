# NestKeep · 原生 iOS App（SwiftUI）

完全重构的 **原生 iOS 客户端**，直连现有 Go 后端 API。目标是「完全 iOS app 风格 + 真·高刷」——
原生层（SwiftUI）天然支持 ProMotion 120Hz，比之前的 Web 壳彻底。

> 与 `src/` 下的 Capacitor Web 壳是**两个独立项目、共享同一后端**。本目录是全新原生工程，
> 不复用任何 Web 代码。

## 技术栈
- **Swift + SwiftUI**（声明式，原生观感）
- 部署目标 **iOS 15.0**（兼容现设备 iPhone 13 Pro / iOS 15.1）
- 网络层 `URLSession` 封装 `APIClient`，自动注入 JWT、`X-Timezone-Offset/-Name`
- 金额统一用 **Int64 分**（与后端一致，避免浮点误差）；所有 ID 为 **String**（后端 `,string` 序列化）
- 高刷：`Info.plist` 的 `CADisableMinimumFrameDurationOnPhone=true` 解锁 CA 60fps 上限

## 目录结构
```
ios-app/
├── NestKeep.xcodeproj/        # 工程文件（由 gen_pbxproj.py 生成）
├── NestKeep/
│   ├── Info.plist             # 含高刷 key、权限等
│   ├── NestKeepApp.swift      # @main 入口
│   ├── Core/                  # APIClient / AuthManager / AppSettings / UI 工具 / 错误模型
│   ├── Models/                # User / Account / Transaction / Category / Tag / ApiModels
│   └── Views/                 # Root / Login / MainTab / Home / Accounts / Transactions / TransactionEdit
├── gen_pbxproj.py             # 生成 project.pbxproj（增删源文件后重跑）
├── build-ios-app.sh           # 构建并导出 IPA
└── exportOptions.plist        # 导出配置
```

## 构建 & 安装（TrollStore）
在 **Mac** 上（Windows 无法编译 Swift）：

```bash
cd ios-app
# 1) Xcode 打开 NestKeep.xcodeproj，Signing & Capabilities 选好你的 Team（免费 Apple ID 即可）
# 2) 构建导出 IPA：
./build-ios-app.sh                # 产物：build/NestKeep.ipa
# 或直接在 Xcode：Product > Archive > Export
# 3) 把 NestKeep.ipa 传到 iPhone，用 TrollStore 打开安装（会重新签名、永久驻留）
```

> 本机（Windows）只能产出源码与工程文件，不能编译/出 IPA；上述步骤必须在 Mac 上完成。

## 后端 API 契约（已核对的关键点）
- 统一响应信封：`{ success, result, errorCode, errorMessage, path }` → Swift 端 `APIEnvelope<T>` 统一解包。
- 登录：`POST /api/authorize.json`，body `{loginName, password}`，返回 `result.token / need2FA / user`。
- 账户：`GET /api/v1/accounts/list.json` → `[Account]`（数组）。
- 分类：`GET /api/v1/transaction/categories/list.json` → `[Category]`（数组）。
- 账单：`GET /api/v1/transactions/list/by_month.json?year=&month=` → `{items:[Transaction], totalCount}`。
- 金额统计：`GET /api/v1/transactions/amounts.json?query=m_<start>_<end>`
  → **返回字典**（按 query 名为键），如 `{"m_1704067200_1706745600":{startTime,endTime,amounts:[{currency,incomeAmount,expenseAmount}]}}`。
- 新增交易：`POST /api/v1/transactions/add.json`，body 见 `Models/ApiModels.swift`。
- ⚠️ 所有 ID 字段（account/category/transaction 的 id、categoryId、sourceAccountId、defaultAccountId 等）
  后端以**字符串**序列化（`json:",string"`），Swift 端必须声明为 `String` 才能正确编解码。
- ⚠️ 金额（`balance` / `sourceAmount` 等）是原始 Int64 **分**，不是字符串。

## MVP 范围（当前已实现）
- 登录（含服务器地址可离线改，默认 `https://example-server.invalid`）
- 主界面 Tab：首页 / 账户 / 账单 / 我的（占位）
- 首页：本月支出/收入、总资产（iOS 卡片风）
- 账户：列表 + 余额
- 账单：按月分页、下拉刷新、月份切换、按日分组
- 新增交易：支出 / 收入 / 转账（金额、账户、分类、时间、备注）

## 后续阶段（未实现）
- 统计页（日/月趋势、分类环形图；iOS 15 需自绘，iOS 16+ 可用原生 Charts）
- 分类/标签管理、设置（默认账户/货币/语言/主题）
- 交易编辑/删除、详情
- AI 识图（multipart 上传）、导入导出、汇率、云同步

## 备注
- 后端 Go 字段为小驼峰，Swift `Decodable` 用 `.useDefaultKeys` 直接对应。
- 分类/账户图标的后端编号是自定义图标字体，原生端用 SF Symbols 近似映射（见 `AccountsView.iconName`）。
