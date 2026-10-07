// import 语句由 scripts/ios-shell-fps-inject.js 合并时加到 AppDelegate.swift 文件顶部（WebKit / ObjectiveC）

/// 解锁 WKWebView 120Hz
///
/// Info.plist 的 CADisableMinimumFrameDurationOnPhone 只解锁 App 进程 Core Animation 的
/// 60fps 上限；WKWebView 的网页内容另被 WebKit 内部偏好 PreferPageRenderingUpdatesNear60FPSEnabled
/// 钉在 60fps（WebKit bug 294338，长期无公开 API）。这里参照 Tauri/Wails 社区插件的实现，
/// 通过私有 API `+[WKPreferences _features]` + `-_setEnabled:forFeature:` 把该偏好关掉。
/// 本 App 经 TrollStore 侧载安装，无 App Store 审核限制。
class ShellFpsInjection {
    static var status = "等待 WebView…"
    private static var applied = false
    private static var attempts = 0
    private static var timer: Timer?

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
        let setSel = NSSelectorFromString("_setEnabled:forFeature:")
        guard prefs.responds(to: setSel) else {
            status = "私有 API 不可用"
            return
        }
        guard let feature = findFeature() else {
            status = "未找到 120Hz 开关"
            return
        }
        let imp = prefs.method(for: setSel)
        typealias SetFn = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
        let fn = unsafeBitCast(imp, to: SetFn.self)
        fn(prefs, setSel, false, feature)
        applied = true
        status = "已关闭 60fps 上限"
    }

    private static func findFeature() -> NSObject? {
        guard let cls = NSClassFromString("WKPreferences") else { return nil }
        let featSel = NSSelectorFromString("_features")
        guard let metaClass = object_getClass(cls) else { return nil }
        let imp: IMP? = class_getMethodImplementation(metaClass, featSel)
        guard let unwrapped = imp else { return nil }
        typealias ClassFn = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>
        let fn = unsafeBitCast(unwrapped, to: ClassFn.self)
        guard let items = fn(cls, featSel).takeUnretainedValue() as? NSArray else { return nil }
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

/// 摇一摇呼出的高刷诊断悬浮窗：
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
    }

    @objc private func onTick(_ link: CADisplayLink) {
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
        textLabel.text = "屏幕上限 \(maxHz)Hz\nCA 渲染 \(caText) fps\n网页 rAF \(rafText) fps\n解锁状态：\(ShellFpsInjection.status)\n点我关闭"
        invalidateIntrinsicContentSize()
    }
}
