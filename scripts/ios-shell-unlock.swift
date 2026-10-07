// import 语句由 scripts/ios-shell-fps-inject.js 合并时加到 AppDelegate.swift 文件顶部（WebKit / ObjectiveC）
// 历史：曾配套 FPS 诊断悬浮窗（v1.6.01.05~v1.6.01.08），2026-10-07 按用户要求移除；
// 需要重新诊断时从 git 历史找回（旧文件名 scripts/ios-shell-fps-hud.swift）。

/// 解锁 WKWebView 120Hz
///
/// Info.plist 的 CADisableMinimumFrameDurationOnPhone 只解锁 App 进程 Core Animation 的
/// 60fps 上限；WKWebView 的网页内容另被 WebKit 内部偏好 PreferPageRenderingUpdatesNear60FPSEnabled
/// 钉在 60fps（WebKit bug 294338，长期无公开 API）。参照 Tauri/Wails 社区插件的实现，
/// 通过私有 API `+[WKPreferences _features]` + `-_setEnabled:forFeature:` 把该偏好关掉，
/// 老系统兜底 `_setBoolValue:forKey:`。版本自适应：iOS 15.1 上两个接口都不存在 → 优雅空转；
/// 新 iOS 上运行时探测到即自动应用。TrollStore 侧载无 App Store 审核限制。
///
/// 崩溃保险丝：调用私有 API 前先持久化"禁用"标记并 synchronize，正常返回后改记"已启用"。
/// 万一私有 API 触发闪退，下次启动读到标记即跳过，保证 App 永远打得开（最坏只闪退一次）。
class ShellFpsInjection {
    private static var applied = false
    private static var attempts = 0
    private static var timer: Timer?
    private static let gateKey = "shell120hz_gate_v1"
    private static let gateDisabled = 2

    static func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { t in
            attempts += 1
            if applied || attempts > 200 {
                t.invalidate()
                timer = nil
                return
            }
            apply()
        }
    }

    static func apply() {
        guard !applied else { return }
        guard let webView = findWebView() else { return }
        let prefs = webView.configuration.preferences

        let defaults = UserDefaults.standard
        if defaults.integer(forKey: gateKey) == gateDisabled {
            NSLog("[ShellFPS] gate=disabled, skip 120Hz unlock")
            applied = true
            return
        }

        let setSel = NSSelectorFromString("_setEnabled:forFeature:")
        let boolSel = NSSelectorFromString("_setBoolValue:forKey:")
        let feature = findFeature()

        guard (prefs.responds(to: setSel) && feature != nil) || prefs.responds(to: boolSel) else {
            NSLog("[ShellFPS] no unlock interface on this OS (iOS 15.0~15.3 web layer cannot be unlocked), skip")
            applied = true
            return
        }

        defaults.set(gateDisabled, forKey: gateKey)
        defaults.synchronize()

        if prefs.responds(to: setSel), let feature = feature {
            let imp = prefs.method(for: setSel)
            typealias SetFn = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
            let fn = unsafeBitCast(imp, to: SetFn.self)
            fn(prefs, setSel, false, feature)
            NSLog("[ShellFPS] disabled web 60fps cap via _features")
        } else {
            let imp = prefs.method(for: boolSel)
            typealias SetBoolFn = @convention(c) (AnyObject, Selector, Bool, NSString) -> Void
            let fn = unsafeBitCast(imp, to: SetBoolFn.self)
            fn(prefs, boolSel, false, "PreferPageRenderingUpdatesNear60FPSEnabled")
            NSLog("[ShellFPS] disabled web 60fps cap via _setBoolValue")
        }

        defaults.set(1, forKey: gateKey)
        defaults.synchronize()
        applied = true
    }

    private static func findFeature() -> NSObject? {
        guard let cls = NSClassFromString("WKPreferences") else { return nil }
        guard let metaClass = object_getClass(cls) else { return nil }
        let featSel = NSSelectorFromString("_features")
        // 注意：class_getMethodImplementation 对不存在的方法返回 forwarding IMP（非 nil），
        // 直接调用会 unrecognized selector 闪退，必须先用 class_getInstanceMethod 判存在
        guard class_getInstanceMethod(metaClass, featSel) != nil else { return nil }
        guard let imp = class_getMethodImplementation(metaClass, featSel) as IMP? else { return nil }
        typealias ClassFn = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let fn = unsafeBitCast(imp, to: ClassFn.self)
        guard let result = fn(cls, featSel),
              let items = result.takeUnretainedValue() as? NSArray else { return nil }
        let keySel = NSSelectorFromString("key")
        for case let feature as NSObject in items {
            guard feature.responds(to: keySel),
                  let key = feature.perform(keySel)?.takeUnretainedValue() as? String else { continue }
            if key == "PreferPageRenderingUpdatesNear60FPSEnabled" {
                return feature
            }
        }
        return nil
    }

    private static func findWebView() -> WKWebView? {
        func dfs(_ view: UIView) -> WKWebView? {
            if let wv = view as? WKWebView { return wv }
            for sub in view.subviews {
                if let found = dfs(sub) { return found }
            }
            return nil
        }
        for scene in UIApplication.shared.connectedScenes {
            if let ws = scene as? UIWindowScene {
                for win in ws.windows {
                    if let found = dfs(win) { return found }
                }
            }
        }
        return nil
    }
}
