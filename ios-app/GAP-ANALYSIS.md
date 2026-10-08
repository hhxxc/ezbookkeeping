# 手机端 Web ↔ iOS 原生：功能与样式差异分析

> 基准：`src/views/mobile/**`（35 个页面，手机端 Web）
> 对照：`ios-app/NestKeep/**`（21 个 Swift 文件，1699 行）
> 统计时间：2026-10-08
> 口径：全部基于实际代码，非推测。后端接口以 `cmd/webserver.go` 注册为准。

---

## 一、总量对比

| 指标 | 手机端 Web | iOS 原生 | 覆盖率 |
|---|---|---|---|
| 页面数 | 35 | 4 个 Tab + 5 个弹层 | ≈ 13% |
| 后端接口调用 | 37 组 | 7 个 | ≈ 19% |
| 代码量 | ≈ 21,000 行 Vue | 1,699 行 Swift | — |

**原生当前只调用了这些接口：**
```
/api/authorize.json
/api/v1/accounts/list.json
/api/v1/systems/version.json
/api/v1/transaction/categories/list.json
/api/v1/transactions/add.json
/api/v1/transactions/amounts.json
/api/v1/transactions/list/by_month.json
```

---

## 二、按模块的功能差异

状态说明：✅ 已对齐　🟡 部分实现　❌ 完全没有

### 1. 首页　🟡

| 能力 | Web 手机端 | iOS 原生 |
|---|---|---|
| 汇总卡 | 本月支出/收入/结余 | ✅ 已有（总资产大卡） |
| 日期范围 | **6 行**：今日/昨日/本周/本月/上月/今年，每行双金额，点进对应账单 | ❌ 只有本月 |
| 金额隐藏 | 眼睛图标切换 | ❌ |
| 最近账单 | 无独立区（靠上面 6 区间） | 🟡 有「最近 5 笔」（Web 没有，属原生增强） |
| 背景图 | 更换首页背景图 | ❌ |
| AI 识图 | 卡片入口 + 相册多选 + 识别后预填 | ❌ 未做 |
| 加号长按 | 弹模板快捷菜单 | ❌ |

接口：`transactions/amounts.json`(✅) `home/backgrounds/upload.json`(❌) `llm/...recognize_receipt_image.json`(❌)

### 2. 账单列表　🟡

| 能力 | Web 手机端 | iOS 原生 |
|---|---|---|
| 分组 | 按月折叠 + 按日分组 + 当日合计 | 🟡 按日分组，无月度合计 |
| 筛选 | 日期范围、分类(多选)、账户(多选)、类型、标签 | ❌ 全无 |
| 搜索 | 描述/金额关键字（防抖） | ❌ |
| 排序 | 时间 / 金额升降 | 🟡 固定时间倒序 |
| 分页 | 无限滚动 | 🟡 按月，`count=200` |
| 视图切换 | 列表 / 日历视图 | ❌ |
| 左滑操作 | 复制 / 加入计划 / 编辑 / 删除 | ❌ |
| 详情页 | 有（View 模式） | ❌ |

接口：`transactions/list.json`(❌，现用 by_month) `delete.json`(❌) `get.json`(❌)

### 3. 交易编辑　🟡

| 能力 | Web 手机端 | iOS 原生 |
|---|---|---|
| 类型 | 支出 / 收入 / 转账 / **余额调整** | 🟡 前三项，缺余额调整 |
| 快速记账布局 | 数字键盘 + 分类网格 + chip 栏 + 「再记一笔」 | ❌ |
| 图片 | 多图上传 + Swiper 轮播 + 删除 | ❌ |
| 标签 | 多选 | ❌ |
| 模板 / 计划账单 | 含频率/起止日期 | ❌ |
| 时区 / 地理位置 | 有 | ❌ |
| 编辑已有 / 复制 | 有 | ❌ |

接口：`add.json`(✅) `modify.json`(❌) `get.json`(❌) `pictures/upload.json`(❌) `templates/*`(❌)

### 4. 统计　❌ 完全没有

Web 手机端有：
- 月/年周期切换，左右翻页 + 自定义日期
- 收支概览卡（支出/收入/结余/日均）
- **每日收支柱状图 / 折线图**（可切换）
- **分类分析饼图** + 分类排行
- **每日报表表格**（含平均值行）
- 多条件筛选（账户/分类/标签/描述）
- 独立统计设置页

接口：`transactions/statistics.json`、`statistics/daily.json`、`statistics/trends.json`、`statistics/asset_trends.json` —— **全部未使用**

### 5. 账户　🟡

| 能力 | Web 手机端 | iOS 原生 |
|---|---|---|
| 净资产汇总 | 净资产/总资产/总负债 + 隐藏切换 | 🟡 首页有总资产 |
| 分组 | 按账户类别分组 + 组内合计 | ❌ 平铺列表 |
| 子账户 | 嵌套展示 | ❌ |
| 新增/编辑/删除 | 有（含图标/颜色/货币/账单日/子账户） | ❌ 只读 |
| 拖拽排序 | 长按拖拽 | ❌ |
| 显隐 | 有 | ❌ |
| 对账单 | 日期范围报告 + 余额趋势图 + 虚拟列表 | ❌ |
| 移动全部账单 | 双确认流程 | ❌ |

接口：`accounts/add|modify|get|hide|move|delete|sub_account/delete`（全 ❌）、`reconciliation_statements.json`(❌)、`transactions/move/all.json`(❌)

### 6. 分类管理　❌

Web：三级分类、增删改、拖拽排序、显隐、**预设分类按语言批量导入**
原生：仅 `categories/list.json` 只读拉取（给新增交易选分类用）

接口缺口：`categories/add|modify|get|hide|move|delete|add_batch`（全 ❌）

### 7. 标签　❌

Web：标签组管理、标签行内增删改、拖拽排序、显隐、筛选「含/排除」状态机
原生：完全没有（`Models/Tag.swift` 模型已建，未使用）

接口缺口：`tags/list|add|add_batch|modify|hide|move|delete`、`tags/groups/*`（全 ❌）

### 8. 模板 / 计划账单　❌

Web：模板列表 + 计划账单、增删改排序、首页加号长按快捷记账
原生：完全没有

接口缺口：`templates/list|add|modify|get|hide|move|delete`（全 ❌）

### 9. 设置　🟡

Web 手机端：主设置页 + 8 个子页
- 字号、时区、应用锁、汇率数据、显示账户余额
- **页面设置**（概览/账单列表/编辑页/账户列表各自的行为开关）
- **账户/分类/标签过滤器**（3 个独立页）
- 账户类别显示顺序
- 设置云同步
- 浏览器缓存管理

原生：「我的」页只有 —— 账号信息、App 版本、后端版本、检查更新、退出登录

接口：`users/settings/cloud/{get,update,disable}.json`（❌）

### 10. 用户 / 安全　❌

Web：用户资料编辑（20+ 字段：语言/货币/日期格式/数字分隔符/金额颜色/财年起始…）、两步验证（QR + 备份码）、设备会话管理、数据管理（统计/导出 CSV/清空）
原生：完全没有

接口缺口：`users/profile/{get,update}.json`、`users/2fa/*`、`tokens/{list,revoke,revoke_all}.json`、`data/{statistics,clear/*,export}`（全 ❌）

### 11. 汇率　❌

Web：基准货币换算列表、设为基准、自定义汇率增删改
原生：完全没有（`exchangerates/*` 全 ❌）

### 12. 登录 / 注册　🟡

| 能力 | Web | 原生 |
|---|---|---|
| 用户名密码登录 | ✅ | ✅ |
| 服务器地址可改 | — | ✅（原生增强） |
| 两步验证 | ✅ passcode / 备份码 | ❌ |
| 忘记密码 | ✅ | ❌ |
| 注册 | ✅ | ❌ |
| 邮箱验证重发 | ✅ | ❌ |
| OAuth2 | ✅ 条件显示 | ❌ |

### 13. 应用锁　❌

Web：6 位 PIN 锁（加密本地 token）+ WebAuthn、独立解锁页
原生：完全没有

### 14. 关于　❌

Web：独立页 —— 版本、构建时间、官网、反馈、帮助、检查更新、**开源许可证**、汇率来源、地图来源
原生：信息散在「我的」页，无独立页、无许可证

---

## 三、样式与交互风格差异

### 3.1 主题色　✅ 一致

| | 值 |
|---|---|
| Web 手机端 | `--ebk-primary-color: 38, 166, 154` = `#26A69A` |
| iOS 原生 | `Theme.brand = #26A69A` |

**主题色完全对齐。** 支出红 / 收入绿也一致。

### 3.2 底部导航　❌ 结构不同

| | 结构 |
|---|---|
| Web 手机端 | **5 个位置**：账单 / 账户 / **中央加号(FAB)** / 统计 / 设置 |
| iOS 原生 | **4 个 Tab**：首页 / 账户 / 账单 / 我的 |

关键差异：
- Web **没有"首页"Tab** —— 首页是启动页，返回靠 Tab；
- Web 有**中央加号**（长按出模板），是记账主入口；
- Web 有**统计 Tab**，原生没有；
- 原生有"首页"Tab，Web 没有。

### 3.3 视觉语言　🟡 风格接近但需统一

| 维度 | Web 手机端 | iOS 原生 |
|---|---|---|
| 卡片 | 白底 16px 圆角 + 单级阴影 | 🟡 已采用（`secondarySystemGroupedBackground` + 16px） |
| 大金额 | 深墨 `#1F2937` | 🟡 走 `Theme`，未统一字色 |
| 列表 | F7 列表 + 左滑操作 | ❌ 无左滑，纯 SwiftUI List |
| 筛选 | Popover 面板 | ❌ |
| 手势 | 下拉刷新、左滑、长按拖拽 | 🟡 仅下拉刷新 |
| 空状态 | 有骨架屏 + 空态图 | 🟡 仅 ProgressView |

---

## 四、优先级建议

> **进度更新（2026-10-08）**：P0 主体已完成（见文末「七、实施进度」）。

### P0 — 记账核心闭环（不做就不算能用）
1. **账单列表增强**：筛选（日期/分类/账户/类型）+ 搜索 + 左滑删除 + 编辑入口
2. **交易编辑增强**：余额调整、编辑已有交易、复制
3. **统计页**：收支概览 + 分类饼图 + 日柱/折线图（iOS 15 需自绘或用 Charts 兼容层）

### P1 — 数据管理必需
4. **账户管理**：增删改、净资产汇总、分组
5. **分类管理**：增删改、排序、显隐
6. **设置页**：主题/字号/时区/默认账户

### P2 — 进阶
7. 标签 + 标签组
8. 模板 / 计划账单、首页加号长按
9. 汇率页
10. 用户资料、两步验证、设备会话

### P3 — 打磨
11. 应用锁（PIN + Face ID）
12. 数据管理 / 导出
13. 关于页 / 许可证
14. 图片上传、AI 识图
15. 首页 6 区间切换、背景图

---

## 五、技术注意点（做之前必须知道）

1. **`amounts.json` 返回字典**（按 query 名为键），不是数组 —— 已踩过。
2. **所有 ID 字段是字符串**（后端 `json:",string"`），含 `categoryId`/`sourceAccountId` 等。
3. **金额是 int64 分**，非字符串。
4. **iOS 15 无原生 Charts**（iOS 16+ 才有）—— 统计图表要么自绘 Path，要么用 `#available` 分支 + 降级方案。
5. **`gen_pbxproj.py` 的 `SWIFT_FILES` 是硬编码列表** —— 每加一个 .swift 都必须手动登记后重跑。
6. **后端契约需逐个核对** —— 部分接口（`statistics/*`、`reconciliation_statements`）的参数格式未验证过。

---

## 六、结论

原生 App 目前是 **"能登录、能看、能记一笔"的最小闭环**，距离"对齐手机端 Web"还有：

- **31 个页面**未实现（占 89%）
- **30 个接口**未接入（占 81%）
- 底部导航结构需要重新设计（5 位 vs 4 Tab）
- 视觉语言骨架已对（主题色/卡片），但**交互层（筛选、左滑、拖拽）全缺**

**好消息**：主题色、卡片风格、金额格式化、后端契约这些"地基"已经打对，后续是**量的堆叠**而非架构返工。

---

## 七、实施进度

### 2026-10-08：P0 主体 + 导航结构对齐（已完成，待真机验证）

**1. 底部导航改为 5 位（结构级对齐）** ✅
- 账单 / 账户 / 中央加号 / 统计 / 设置，与 Web `main-tabbar` 一致
- 首页内容并入账单页顶部，删除独立的 `HomeView.swift`（Web 本就没有首页 Tab）
- 中央加号 56×56 主色圆钮、上探 28pt；短按新增交易、长按出模板快捷菜单
- 视觉与 Web 对齐：完全透明背景、无顶部分隔线
- 采用 `ZStack + opacity` 保活各页，切 Tab 不丢滚动位置与状态
- 浮层导航避让：环境值 `mainTabBarInset` + 各页 `safeAreaInset(edge: .bottom)`

**2. 账单列表增强** ✅
- 顶部汇总卡：总资产 + 本月支出/收入/结余（原首页内容）
- 日分组头显示当日支出/收入合计
- 左滑删除（`POST /transactions/delete.json`）、左滑编辑
- 点击行进入交易详情页

**3. 交易编辑增强** ✅
- 支持编辑已有交易（`POST /transactions/modify.json`）
- 支持复制为新交易（`mode: .duplicate`，不带 id 走 add）
- 新增「余额调整」类型；分类按收支类型过滤
- 金额换算统一 `NSDecimalNumber`，规避 Xcode 26 下 `Decimal * 100` 被推断为 Float16

**4. 新增交易详情页** ✅ `TransactionDetailView.swift`
- 展示类型/金额/分类/账户/时间/备注，提供「复制为新交易」「编辑」入口

**5. 新增统计页** ✅ `StatisticsView.swift`
- 收支概览（支出/收入/结余/日均支出），月份左右切换
- 支出/收入切换，分类占比环形图（`Canvas` 自绘）+ 分类排行
- 每日收支柱状图（`Path` 自绘）
- iOS 15 无原生 Charts，全部自绘实现

**新增/修改的 Swift 文件**（`gen_pbxproj.py` 已同步，共 22 个源文件）：
- 新增 `Views/StatisticsView.swift`、`Views/TransactionDetailView.swift`
- 删除 `Views/HomeView.swift`
- 改 `Views/MainTabView.swift`、`TransactionsView.swift`、`TransactionEditView.swift`、
  `AccountsView.swift`、`SettingsView.swift`、`Models/Transaction.swift`

**后端契约**（本轮核对）：
- `id` / `categoryId` / `sourceAccountId` / `destinationAccountId` 均为字符串
- `destinationAccountId` 非转账时传 `"0"`，`destinationAmount` 传 `0`
- 统计项 `amount` 带符号：负=支出、正=收入
- `statistics.json` / `statistics/daily.json` 需 `use_transaction_timezone=true`

**环境坑**：本机 git 直连 `github.com:443` 不通，代理（`127.0.0.1:9876`）只放行
`api.github.com`；改用 `gh api` + Git Data API 推送。**注意：API 更新 ref 不会触发
workflow**，需另做一次真实 push 或手动 dispatch 才能出包。

### 2026-10-08（第二轮）：P1 主体 —— 筛选/搜索、账户管理、分类管理、标签/图片

**1. 账单列表筛选与搜索** ✅
- 新增 `TransactionFilter`：类型、分类多选、账户多选、日期范围、排序（时间/金额 × 升降）
- 筛选态走 `transactions/list.json`（`category_ids` / `account_ids` / `type` / `keyword` /
  `sort_by` / `sort_order`），无筛选仍走 `by_month.json`（按月浏览语义）
- 关键字搜索 300ms 防抖；空态区分「本月无账单」与「无匹配结果」并给「清除筛选」
- **契约坑**：`max_time` / `min_time` 是**毫秒级**时间序列 id（`Unix 秒 × 1000`），
  不是秒；结束日需取当日 23:59:59.999（`次日 0 点 × 1000 - 1`）

**2. 交易编辑补齐标签 / 图片** ✅
- 标签多选（按标签组分组展示，`transaction/tags/groups/list.json`）
- 图片上传（`transaction/pictures/upload.json`，multipart，表单字段名 `picture`），
  新增 `Core/PictureUploader.swift`；选图用 PHPicker（免相册权限）
- `add` / `modify` 请求补 `tagIds` / `pictureIds` / `geoLocation` / `clientSessionId`

**3. 账户管理** ✅
- 净资产汇总卡（总资产 / 总负债 / 净资产）+ 金额隐藏开关
- 按类别分组、子账户缩进展示
- 新增 / 编辑 / 删除 / 隐藏（`accounts/add|modify|delete|hide.json`）
- 新增 `Views/AccountEditView.swift`、`Models/AccountRequests.swift`
  （图标 / 颜色 / 货币 / 初始余额与时间 / 信用卡账单日）

**4. 分类管理** ✅
- 支出 / 收入 / 转账切换，一级 + 子分类展示
- 增删改 / 显隐（`categories/add|modify|delete|hide.json`）
- 「设置 → 分类管理」入口；新增 `Views/CategoriesView.swift`、`Models/CategoryRequests.swift`

**新增/修改的 Swift 文件**（`gen_pbxproj.py` 已同步，共 **27 个源文件**）：
- 新增 `Core/PictureUploader.swift`、`Models/AccountRequests.swift`、
  `Models/CategoryRequests.swift`、`Views/AccountEditView.swift`、`Views/CategoriesView.swift`
- 改 `Views/TransactionsView.swift`（筛选/搜索）、`Views/TransactionEditView.swift`（标签/图片）、
  `Views/AccountsView.swift`（重写）、`Views/SettingsView.swift`（分类管理入口）、
  `Models/{Tag,Transaction,ApiModels}.swift`

**iOS 15 编译坑（本轮踩到）**：
1. `@ViewBuilder` 函数**自递归**（账户行嵌子账户）→ `some View` 自引用、opaque 类型推断失败；
   改为把「父 + 子」拍平成数组再逐行渲染
2. `Button.bold()` 是 **iOS 16+**（`View.bold()`）；iOS 15 需 `.font(.body.weight(.semibold))`
   （`Text.bold()` 才是 iOS 15 可用）

**交付**：IPA `NestKeep-native-ios-app-20.ipa`（1.6.3 构建号 20，817KB，已发 NAS；
`latest.json` version=1.6.4；GitHub Release `v1.6.4`）。

### 2026-10-08（第五轮）：P3 收尾 —— 6 区间 / 日历 / AI 识图 / 汇率 / 背景图 / 应用锁

至此 GAP-ANALYSIS 第二章列出的 **14 个模块全部落地**，P0/P1/P2/P3 关闭。

**1. 首页 6 区间切换 + 金额隐藏** ✅
- 汇总卡下方新增「日期范围卡」：今日 / 昨日 / 本周 / 本月 / 上月 / 今年 **6 行**，
  每行左侧 32×32 圆角色块图标徽章（配色照 Web：today `#26A69A`、yesterday `#8E7CC3`、
  week `#5B8DB8`、month `#DD9437`、lastMonth `#879BAB`、year `#5DA65C`），
  中间标题 + 日期副标题，右侧收入（绿）/ 支出（红）双金额；点击整行 → 按该区间筛选账单
- `loadAmounts()` 从「只查本月」改为**一次请求拉 6 个区间**：
  `query=today_s_e|yesterday_s_e|thisWeek_s_e|thisMonth_s_e|lastMonth_s_e|thisYear_s_e`
  + `use_transaction_timezone=true`；返回是**字典**（按区间名为键）
- 边界口径完全对齐 Web 的 `initTransactionDateRange`；本周以**周一**为第一天
- 汇总卡右上角加**眼睛图标**切换金额隐藏（总资产 + 三个 miniStat + 6 行金额联动），
  状态持久化到 `UserDefaults`（`nestkeep.hideAmounts`）

**2. 日历视图** ✅
- 账单页工具条新增「列表 / 日历」切换按钮（对应 Web 的 `TransactionListPageType`）
- 新增 `Views/TransactionCalendarView.swift`：自绘月历网格（`LazyVGrid`，
  iOS 15 无原生日历组件），每格显示当日支出/收入（紧凑格式 `1.2万`），
  今日高亮，点某天 → 按该日筛选
- 数据走 `transactions/statistics/daily.json`（与统计页同口径）

**3. AI 识图记账** ✅
- 新增 `Core/ReceiptRecognizer.swift`：multipart 上传，表单字段名 **`image`**
  （注意不是 `picture`），返回**数组**（兼容旧版单对象），字段 `type/time/categoryId/
  sourceAccountId/destinationAccountId/sourceAmount/destinationAmount/tagIds/comment`
- 新增 `Views/AIReceiptView.swift`：选图 → 识别 → 结果卡列表 → 点任一条
  进「新增交易」并**预填**（`Recognized.asPrefillTransaction()` 包装成 `Transaction`）
- 入口：首页 `.home-ai-entry-card` 同款卡片 + 中央加号长按菜单「AI 识图记账」
- **能力探测**：该路由仅在 `ReceiptImageRecognitionLLMConfig != nil &&
  LLMProvider != "" && TransactionFromAIImageRecognition` 时注册，否则 404。
  新增 `Core/ServerSettings.swift` 解析后端下发的
  `GET /mobile/server_settings.js`（`window.EZBOOKKEEPING_SERVER_SETTINGS['llmt']=1;`，
  **键名是单引号**），据此决定入口显隐，避免死入口

**4. 汇率页** ✅
- 新增 `Models/ExchangeRate.swift` + `Views/ExchangeRatesView.swift`
- 展示 `exchange_rates/latest.json`：基准货币、汇率列表（按代码排序）、数据源（可点击
  跳外链）、更新时间
- 左滑删除自定义汇率（`exchange_rates/user_custom/delete.json`，基准货币不可删，
  后端返回 `ErrCannotDeleteExchangeRateForDefaultCurrency`）
- 右上角 `+` 新增自定义汇率：`exchange_rates/user_custom/update.json`
  请求体 `{currency(3位), rate(字符串)}`；「1 默认货币 = N 目标货币」的语义与 Web 一致
- 入口：「设置 → 显示与汇率 → 汇率」

**5. 首页背景图** ✅
- 新增 `Core/HomeBackground.swift`：上传走
  `POST /api/v1/home/backgrounds/upload.json`（multipart，字段名 `picture`，返回 `{url}`），
  与 Web 的 `uploadHomeBackground` 一致；该路由在 `EnableTransactionPictures` 下注册
- 展示时把返回的**相对路径**拼成完整 URL 并带 `?token=`（图片接口按 token 鉴权）
- 汇总卡底图改为 `AsyncImage` + 主色渐变压暗（`opacity 0.72`）保证白字可读
- 入口：「设置 → 显示与汇率 → 首页背景图」（上传 / 更换 / 移除，未开启图片功能时提示）

**6. 应用锁（PIN + 生物识别）** ✅
- 新增 `Core/AppLockManager.swift`：**不存 PIN 明文**，用
  `key = SHA256("EBK_LOCK_SECRET_" + PIN + "|" + salt)` 派生 AES-256 密钥，
  用它对 token 做 AES-GCM 加密后落盘；明文 token **只在内存**，解锁后才注入 `AuthManager`
- `AuthManager` 新增 `restoreToken` / `clearInMemoryTokenPreservingStorage` /
  `removePlaintextTokenFromStorage` / `persistPlaintextTokenWithStorage`，
  并在 `init` 中识别「有加密凭证 → 视为已登录但未解锁」
- 新增 `Views/AppLockView.swift`（6 位 PIN 数字键盘 + Face ID/Touch ID + 重新登录兜底）
- 新增 `Views/AppLockSettingsView.swift`（开关 / 改 PIN / 生物识别开关）
- `RootView` 三态：未登录 → 登录页；已登录未解锁 → 解锁页；否则主界面；
  监听 `didEnterBackground` 自动重新上锁
- `Info.plist` 新增 `NSFaceIDUsageDescription`（缺了系统会直接拒绝评估生物识别）
- 入口：「设置 → 安全 → 应用锁」

**iOS 15 / 契约坑（本轮新踩）**：
1. `ServerSettings` 解析：后端 `appendEncodedString` 用的是**单引号**
   （`['llmt']=1`），最初按双引号写解析恒为空
2. 应用锁开启后 UserDefaults 里不能再留明文 token，否则锁形同虚设；
   `AuthManager.init` 必须靠「存在加密凭证」判断已登录，否则解锁页永远不出现

**新增 / 修改的 Swift 文件**（`gen_pbxproj.py` 已同步，共 **45 个源文件**）：
- 新增 `Core/{ServerSettings,ReceiptRecognizer,HomeBackground,AppLockManager}.swift`、
  `Models/ExchangeRate.swift`、`Views/{AIReceiptView,ExchangeRatesView,
  HomeBackgroundSettingsView,AppLockView,AppLockSettingsView,TransactionCalendarView}.swift`
- 改 `Views/{TransactionsView,MainTabView,SettingsView,RootView}.swift`、
  `Core/{AuthManager,PictureUploader}.swift`、`NestKeep/Info.plist`、`gen_pbxproj.py`

**待验证**：云端构建（`build-native-ios.yml`，push `native-ios-app` 触发）需通过；
真机验证 6 区间金额、日历着色、AI 识图预填、应用锁冷启动流程。

---

### 2026-10-08（第六轮）：账单页「照 Web 重做视觉」

用户对比截图后反馈「差异太大 样式也是」，遂把原生账单页顶部（原首页内容）**逐项复刻**
Web 手机端 `HomePage.vue` 的视觉规格，而不是沿用早期的「主题色卡片」自创样式。

**逐项对照表**

| 元素 | Web 规格（`HomePage.vue`） | 原生实现 |
|---|---|---|
| 汇总卡底 | `--hp-card:#FFFFFF`（暗 `#252530`），圆角 `--ebk-card-border-radius` | `HomePalette.card`，圆角 16 |
| 卡外边距 | `calc(safe-area-top + 24px) 16px 16px` | List 首行占位 30 + insets 16 |
| 左上标题 | `.home-summary-label` 18px/600，`thisMonth.displayTime`（走 `MMMM`→「**十月**」中文大写） | 18pt semibold，「十月」 |
| 支出徽标 | `.expense-badge`：`#FCEBEA` 底 / `#D0443F` 字，13px/600，`padding:2px 10px`，圆角 8 | 完全一致 |
| 大金额 | `.home-summary-amount` `font-size:2em;font-weight:600`，色 `--hp-ink` | 34pt semibold，`HomePalette.ink` |
| 眼睛图标 | `.ebk-hide-icon` 19px，色 `--hp-secondary`，位于金额**之后** | 19pt，secondary，金额右侧 |
| 底部指标 | `.home-summary-metrics`：当月收入（`--hp-income:#1E9E6F`）· `.home-summary-metric-divider` · 月结余；label 13px、value 15px/600 | 13pt / 15pt semibold，`.monospacedDigit` |
| 右上按钮 | `.home-card-gallery-btn` 30×30 圆角8，`rgba(0,0,0,0.04)` 底 | 一致 |
| 导航栏 | **无**（F7 首页不用 navbar） | 去掉 `NavigationView`，月份/筛选/新增改悬浮 `topBar` |
| 背景图态 | `.has-bg`：文字转白 + `text-shadow`，`gallery-btn` 转 `rgba(0,0,0,0.3)` | `HomeShadow` + 白色系 + `black.opacity(0.3)` |
| 区间行 | `.overview-period-icon` 32×32 圆角10 同色 13~16% 透明底；标题 17px；footer 13px；金额 `small` 14px | 一致 |
| 区间副标题 | `displayDateRange`：today/yesterday=`formatDateTimeToLongDate`；week/month/lastMonth=`startTime`–`endTime`(`formatDateTimeToLongMonthDay`)；year=`…LongYear` | 完全按此格式化 |
| AI 卡 | `.home-ai-entry-card`：icon 40×40 圆角12 主色 13% 底；标题 15px/600；副标题 12px | 一致 |
| 底部 Tab | Details / Accounts / + / Statistics / Settings | 「详情」/「账户」/ + /「统计」/「设置」 |

**关键决策：新增 `HomePalette` 而不是复用 `Theme`**
Web 首页的支出/收入色是低饱和的 `#D0443F` / `#1E9F6F`，与全局 `Theme.expense/income`
（鲜红/鲜绿）**不是同一套**。之前原生把两者混用，是「看起来不像」的主因之一。
`HomePalette` 用 `UIColor { $0.userInterfaceStyle == .dark ? ... }` 生成动态色，
同时覆盖深色变体（`#252530` / `#E8EAED` / `#F87171` / `#34D399`）。

**移除 `NavigationView` 的连带影响**
原 `.toolbar` 里的月份切换、列表/日历切换、筛选、新增按钮随之失效，改为自建 `topBar`
用 `.overlay(alignment: .top)` 悬浮；`List` 首行插入 30pt 透明占位行避免内容被遮挡，
`topBar` 背景用**不透明**分组底色（半透明会导致滚动文字透出、观感脏）。

**背景图蒙层修正**
旧实现是「主色渐变压暗」，与 Web 的「原图 + 白字 + 投影」不符 → 改为中性
`Color.black.opacity(0.28)` 压暗 + 文字投影。

**改动文件**：`Core/UI.swift`（新增 `HomePalette`、`import UIKit`）、
`Views/TransactionsView.swift`（主重构）、`Views/MainTabView.swift`（文案与注释）、
`Views/HomeBackgroundSettingsView.swift`（提示文案）

**验证**：commit `f0ca6dc3` → 云端 run `37748185176` **成功**（1m21s）。源文件仍 45 个。
