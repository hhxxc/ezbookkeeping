import Foundation
import os

/// 冷启动各阶段耗时打点。
///
/// - t0 = 进程启动时刻（sysctl kern.proc，早于 main），每个阶段报告「距进程启动」的
///   绝对毫秒数，包含 SwiftUI/动态链接等我们控制之外的启动开销，数字更真实；
/// - 输出三路：os_signpost（Instruments 可视化）、Logger（控制台按 subsystem 过滤）、
///   `stages`（关于页直接展示真机实测值）；
/// - 同名阶段只记第一次（warm 切 Tab / 二次 onAppear 不会重复记录）。
@MainActor
final class StartupMetrics: ObservableObject {
    static let shared = StartupMetrics()

    struct Stage: Identifiable {
        let name: String
        let ms: Double
        var id: String { name }
    }

    @Published private(set) var stages: [Stage] = []

    private static let subsystem = Bundle.main.bundleIdentifier ?? "nestkeep"
    private let signposter = OSSignposter(subsystem: StartupMetrics.subsystem, category: "startup")
    private let logger = Logger(subsystem: StartupMetrics.subsystem, category: "startup")

    private init() {}

    /// 进程启动（内核创建进程）到现在的毫秒数
    private static var msSinceProcessStart: Double {
        Date().timeIntervalSince1970 * 1000 - processStartEpochMs
    }

    /// 进程启动时刻（epoch 毫秒），sysctl KERN_PROC 读取
    private static let processStartEpochMs: Double = {
        var kinfo = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &kinfo, &size, nil, 0) == 0 else { return 0 }
        return (Double(kinfo.kp_proc.tv_sec) + Double(kinfo.kp_proc.tv_usec) / 1_000_000) * 1000
    }()

    /// 记录一个启动阶段（同名只记第一次）
    func markOnce(_ name: String) {
        guard !stages.contains(where: { $0.name == name }) else { return }
        let ms = Self.msSinceProcessStart
        stages.append(Stage(name: name, ms: ms))
        signposter.emitEvent("startup.\(name, privacy: .public)", "\(Int(ms))ms")
        logger.notice("[StartupMetrics] \(name, privacy: .public) +\(Int(ms))ms since process start")
    }
}
