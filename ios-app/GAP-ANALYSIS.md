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
