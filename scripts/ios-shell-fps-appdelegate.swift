
    // MARK: - 高刷诊断 HUD（摇一摇开关）

    private var shellFpsHud: ShellFpsHud?

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            toggleShellFpsHud()
        } else {
            super.motionEnded(motion, with: event)
        }
    }

    private func toggleShellFpsHud() {
        if let hud = shellFpsHud {
            hud.shutdown()
            shellFpsHud = nil
            return
        }
        let keyWindow: UIWindow? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        guard let win = keyWindow else { return }
        let hud = ShellFpsHud()
        win.addSubview(hud)
        shellFpsHud = hud
    }
