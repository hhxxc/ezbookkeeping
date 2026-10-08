import SwiftUI
import UIKit

/// 关于页：版本、构建时间、官网/反馈入口、开源许可证（对齐 Web 的关于页）
struct AboutView: View {
    @ObservedObject private var updateStore = UpdateStore.shared
    @State private var showLicenses = false

    private let repoURL = URL(string: "https://github.com/hhxxc/ezbookkeeping")!
    private let websiteURL = URL(string: "https://ezbookkeeping.mayswind.net/")!

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "house.lodge.fill")
                        .font(.system(size: 46))
                        .foregroundColor(.white)
                        .frame(width: 84, height: 84)
                        .background(
                            LinearGradient(colors: [Theme.brand, Theme.brand.opacity(0.75)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .cornerRadius(20)
                    Text("巢记 NestKeep").font(.headline)
                    Text("版本 \(UpdateChecker.currentAppVersion) (\(UpdateChecker.currentBuildNumber))")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section(header: Text("信息")) {
                HStack {
                    Text("后端版本")
                    Spacer()
                    Text(updateStore.serverVersion?.version ?? "—").foregroundColor(.secondary)
                }
                if let commit = updateStore.serverVersion?.commitHash, !commit.isEmpty {
                    HStack {
                        Text("后端提交")
                        Spacer()
                        Text(String(commit.prefix(8))).foregroundColor(.secondary)
                    }
                }
                if let buildTime = updateStore.serverVersion?.buildTime, !buildTime.isEmpty {
                    HStack {
                        Text("后端构建时间")
                        Spacer()
                        Text(buildTime).foregroundColor(.secondary).font(.caption)
                    }
                }
            }

            Section(header: Text("链接")) {
                Link(destination: websiteURL) { Label("官网", systemImage: "globe") }
                Link(destination: repoURL) { Label("源代码（GitHub）", systemImage: "chevron.left.forwardslash.chevron.right") }
                Link(destination: repoURL.appendingPathComponent("issues")) {
                    Label("问题反馈", systemImage: "exclamationmark.bubble")
                }
                Button { showLicenses = true } label: {
                    Label("开源许可证", systemImage: "doc.text")
                }
                .foregroundColor(.primary)
            }

            Section(header: Text("数据来源")) {
                Text("汇率数据：European Central Bank / 各银行公开数据")
                    .font(.caption).foregroundColor(.secondary)
                Text("地图数据：OpenStreetMap contributors")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle("关于")
        .sheet(isPresented: $showLicenses) {
            LicenseView()
        }
    }
}

/// 开源许可证清单（本 App 依赖的主要第三方组件）
struct LicenseView: View {
    @Environment(\.dismiss) private var dismiss

    private let licenses: [(String, String)] = [
        ("ezBookkeeping", "MIT License\n\nCopyright (c) mayswind\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction."),
        ("Framework7", "MIT License\n\nCopyright (c) Vladimir Kharlampidi"),
        ("Vue.js", "MIT License\n\nCopyright (c) Evan You"),
        ("Go", "BSD 3-Clause License\n\nCopyright (c) 2009 The Go Authors"),
        ("Gin Web Framework", "MIT License\n\nCopyright (c) 2014 Manuel Martínez-Almeida"),
        ("SwiftUI / UIKit", "Apple Inc. — 随 iOS SDK 提供")
    ]

    var body: some View {
        NavigationView {
            List {
                ForEach(licenses, id: \.0) { item in
                    Section(header: Text(item.0)) {
                        Text(item.1)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("开源许可证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
