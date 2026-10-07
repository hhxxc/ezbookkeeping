
    // MARK: - 高刷诊断 HUD（摇一摇开关）

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            ShellFpsInjection.toggleHud()
        } else {
            super.motionEnded(motion, with: event)
        }
    }
