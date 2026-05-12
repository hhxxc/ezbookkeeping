# 巢记 / NestKeep

> 轻量级、自托管的个人记账应用，移动端+桌面端双端适配，Docker 一键部署。

[![License](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)

> 📌 本项目基于 [mayswind/ezBookkeeping](https://github.com/mayswind/ezbookkeeping) 二次开发，感谢原作者的杰出工作。

## 简介

巢记是一款面向个人的轻量记账工具，帮助你随手记录每一笔收支。支持移动端 PWA（可添加到手机主屏幕像原生 App 一样使用）和桌面端 Web 界面，数据完全自托管，隐私安全可控。

- 🏠 **私有部署** — Docker 一行命令跑起来，数据留在自己手里
- 📱 **移动优先** — iOS/Android 添加到桌面即用，PWA 离线可用
- 🌙 **深色模式** — 明暗主题自动切换
- 🤖 **AI 智能** — 拍小票自动识别金额、分类、时间
- 📊 **多维统计** — 收支趋势、分类占比一目了然
- 💱 **多币种** — 自动汇率更新

## 功能亮点

- **双端适配** — 移动端 iOS 风格交互，桌面端 Materio 管理布局
- **AI 图像识别** — 拍照识别小票/发票，自动填单
- **二级分类** — 收支类别支持两级层级
- **多账户** — 支持现金、银行卡、信用卡等多种账户
- **周期账单** — 固定收支定时提醒
- **地图定位** — 交易记录带地图位置
- **数据导入** — 支持支付宝/微信账单、CSV、OFX、QIF、GnuCash 等多种格式
- **数据导出** — Excel、CSV 格式导出
- **安全** — 双因素认证(2FA)、OIDC 外部登录、应用锁(PIN/WebAuthn)
- **多语言** — 内置 20 种语言翻译

## 截图

### 移动端

![NestKeep Mobile](https://raw.githubusercontent.com/wiki/mayswind/ezbookkeeping/img/mobile/en.png)

### 桌面端

![NestKeep Desktop](https://raw.githubusercontent.com/wiki/mayswind/ezbookkeeping/img/desktop/en.png)

## 快速开始

### Docker 部署

```bash
docker run -p8080:8080 mayswind/ezbookkeeping
```

访问 `http://localhost:8080` 即可使用。

### 二进制安装

从 [Releases](https://github.com/mayswind/ezbookkeeping/releases) 下载对应平台二进制文件：

**Linux / macOS**
```bash
./ezbookkeeping server run
```

**Windows**
```powershell
.\ezbookkeeping.exe server run
```

### 从源码构建

需要 Golang、GCC、Node.js 和 NPM。

**Linux / macOS**
```bash
./build.sh package -o nestkeep.tar.gz
```

**Windows**
```powershell
.\build.bat package -o nestkeep.zip
```

### 开发环境 (Windows)

需要安装 MSYS2 (MinGW64) 和 [air](https://github.com/air-verse/air)：

**1. 启动前端开发服务器：**
```powershell
npm run serve
```

**2. 启动后端热重载：**
```powershell
$env:Path = "C:\msys64\mingw64\bin;" + $env:Path; $env:CGO_ENABLED="1"; air
```

访问 `http://localhost:15080/`，前后端均支持热更新。

## 文档

- [English](https://ezbookkeeping.mayswind.net)
- [中文 (简体)](https://ezbookkeeping.mayswind.net/zh_Hans)

## 鸣谢

本项目基于 [ezBookkeeping](https://github.com/mayswind/ezbookkeeping)（作者 [@mayswind](https://github.com/mayswind)），采用 MIT 协议开源。感谢原项目作者及所有[贡献者](https://github.com/mayswind/ezbookkeeping/graphs/contributors)。

## 协议

[MIT](./LICENSE)
