// import 语句由 scripts/ios-shell-fps-inject.js 合并时加到 AppDelegate.swift 文件顶部（WebKit / ObjectiveC）

/// 解锁 WKWebView 120Hz
///
/// Info.plist 的 CADisableMinimumFrameDurationOnPhone 只解锁 App 进程 Core Animation 的
/// 60fps 上限；WKWebView 的网页内容另被 WebKit 内部偏好 PreferPageRenderingUpdatesNear60FPSEnabled
/// 钉在 60fps（WebKit bug 294338，长期无公开 API）。这里参照 Tauri/Wails 社区插件的实现，
/// 通过私有 API `+[WKPreferences _features]` + `-_setEnabled:forFeature:` 把该偏好关掉。
/// 本 App 经 TrollStore 侧载安装，无 App Store 审核限制。
///
/// 崩溃保险丝：调用私有 API 前先持久化"禁用"标记并 synchronize，正常返回后改记"已启用"。
/// 万一私有 API 在某些 iOS 版本上触发闪退，下次启动读到标记即跳过，保证 App 永远打得开；
/// 最坏情况只闪退一次。注意 UserDefaults 随 IPA 升级（同 bundle id 覆盖安装）保留，重装才清空。
class ShellFpsInjection {
    static var status = "等待 WebView…"
    private static var applied = false
    private static var attempts = 0
    private static var timer: Timer?
    private static var hud: ShellFpsHud?
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
        // 首启自动弹一次诊断悬浮窗（12 秒后自动消失），不用摇也能直接确认解锁状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showHud(autoHideAfter: 12)
        }
    }

    // MARK: 悬浮窗管理

    static func toggleHud() {
        if let current = hud {
            current.shutdown()
            return
        }
        showHud(autoHideAfter: nil)
    }

    static func showHud(autoHideAfter seconds: TimeInterval?) {
        guard hud == nil else { return }
        let keyWindow: UIWindow? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        guard let win = keyWindow else { return }
        let view = ShellFpsHud()
        win.addSubview(view)
        hud = view
        if let seconds = seconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak view] in
                view?.shutdown()
            }
        }
    }

    static func hudDidClose(_ view: ShellFpsHud) {
        if hud === view {
            hud = nil
        }
    }

    // MARK: 120Hz 解锁

    static func apply() {
        guard !applied else { return }
        guard let webView = findWebView() else { return }
        let prefs = webView.configuration.preferences

        let setSel = NSSelectorFromString("_setEnabled:forFeature:")
        guard prefs.responds(to: setSel) else {
            status = "私有 API 不可用"
            return
        }
        guard let feature = findFeature() else {
            status = "未找到 120Hz 开关"
            return
        }

        let defaults = UserDefaults.standard
        if defaults.integer(forKey: gateKey) == gateDisabled {
            status = "已自动禁用（上次触发闪退）"
            applied = true
            return
        }
        defaults.set(gateDisabled, forKey: gateKey)
        defaults.synchronize()

        let imp = prefs.method(for: setSel)
        typealias SetFn = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
        let fn = unsafeBitCast(imp, to: SetFn.self)
        fn(prefs, setSel, false, feature)

        defaults.set(1, forKey: gateKey)
        defaults.synchronize()
        applied = true
        status = "已关闭 60fps 上限"
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

/// 高刷诊断悬浮窗（首启自动弹 12 秒，之后摇一摇呼出）：
/// - 屏幕上限：设备支持的最高刷新率（13 Pro 应为 120）
/// - CA 渲染：App 进程 Core Animation 实际帧率（Info.plist key 生效应 ≈120）
/// - 网页 rAF：WKWebView 里 requestAnimationFrame 实际频率（私有 API 生效应 ≈120）
/// 点按悬浮窗关闭。
class ShellFpsHud: UIView {
    private let textLabel = UILabel()
    private var displayLink: CADisplayLink?
    private var frameCount = 0
    private var windowStart: CFTimeInterval = 0
    private var caFps: Double = 0
    private var rafFps = 0
    private var rafTimer: Timer?
    private var probing = false
    private var lastFrameTs: CFTimeInterval = 0
    private var frameIntervals: [Double] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0, alpha: 0.72)
        layer.cornerRadius = 10
        translatesAutoresizingMaskIntoConstraints = false

        textLabel.textColor = .white
        textLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        textLabel.numberOfLines = 0
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textLabel)

        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        ])
        widthAnchor.constraint(lessThanOrEqualToConstant: 240).isActive = true

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shutdown)))

        if #available(iOS 15.0, *) {
            let link = CADisplayLink(target: self, selector: #selector(onTick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            displayLink = link
        } else {
            displayLink = CADisplayLink(target: self, selector: #selector(onTick(_:)))
        }
        displayLink?.add(to: .main, forMode: .common)
        updateText()
        scheduleRafProbe()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let win = window else { return }
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: win.safeAreaLayoutGuide.topAnchor, constant: 8),
            trailingAnchor.constraint(equalTo: win.safeAreaLayoutGuide.trailingAnchor, constant: -8)
        ])
    }

    @objc func shutdown() {
        displayLink?.invalidate()
        displayLink = nil
        rafTimer?.invalidate()
        rafTimer = nil
        removeFromSuperview()
        ShellFpsInjection.hudDidClose(self)
    }

    @objc private func onTick(_ link: CADisplayLink) {
        if lastFrameTs > 0 {
            frameIntervals.append((link.timestamp - lastFrameTs) * 1000.0)
            if frameIntervals.count > 180 {
                frameIntervals.removeFirst(frameIntervals.count - 180)
            }
        }
        lastFrameTs = link.timestamp

        if windowStart == 0 {
            windowStart = link.timestamp
            frameCount = 0
            return
        }
        frameCount += 1
        let elapsed = link.timestamp - windowStart
        if elapsed >= 1 {
            caFps = Double(frameCount) / elapsed
            frameCount = 0
            windowStart = link.timestamp
            updateText()
        }
    }

    private func scheduleRafProbe() {
        guard displayLink != nil else { return }
        guard let webView = findWebView() else {
            rafTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in self?.scheduleRafProbe() }
            return
        }
        probing = true
        let js = "(new Promise(function(res){var n=0,t0=performance.now();(function f(){n++;if(performance.now()-t0<1000){requestAnimationFrame(f)}else{res(n)}})()}))"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self = self, self.displayLink != nil else { return }
                self.probing = false
                if let n = result as? Int { self.rafFps = n }
                self.updateText()
                self.rafTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in self?.scheduleRafProbe() }
            }
        }
    }

    private func findWebView() -> WKWebView? {
        guard let win = window else { return nil }
        func dfs(_ view: UIView) -> WKWebView? {
            if let wv = view as? WKWebView { return wv }
            for sub in view.subviews {
                if let found = dfs(sub) { return found }
            }
            return nil
        }
        return dfs(win)
    }

    private func updateText() {
        let maxHz = Int(UIScreen.main.maximumFramesPerSecond)
        let caText = caFps > 0 ? String(format: "%.0f", caFps) : "…"
        let rafText = rafFps > 0 ? "\(rafFps)" : (probing ? "测量中" : "…")
        // 掉帧率：近 180 帧里帧间隔超过最优间隔 1.6 倍的占比，量化"卡不卡"
        var dropText = "…"
        if frameIntervals.count >= 30, let best = frameIntervals.min(), best > 0 {
            let drops = frameIntervals.filter { $0 > best * 1.6 }.count
            dropText = "\(drops * 100 / frameIntervals.count)%"
        }
        textLabel.text = "屏幕上限 \(maxHz)Hz\nCA 渲染 \(caText) fps\n网页 rAF \(rafText) fps\n掉帧 \(dropText)\n解锁状态：\(ShellFpsInjection.status)\n点我关闭"
        invalidateIntrinsicContentSize()
    }
}
