import SwiftUI
import Combine

/// 设备 / 会话管理（对齐 Web 的会话列表页）
@MainActor
final class SessionsViewModel: ObservableObject {
    @Published var tokens: [TokenInfo] = []
    @Published var isLoading = false
    @Published var error: String?

    func load() async {
        isLoading = true
        error = nil
        do {
            tokens = try await APIClient.shared.request("/api/v1/tokens/list.json")
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func revoke(_ token: TokenInfo) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/tokens/revoke.json", method: .POST, body: TokenRevokeRequest(tokenId: token.tokenId)
            )
            tokens.removeAll { $0.tokenId == token.tokenId }
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 撤销全部（当前会话也会失效，需重新登录）
    func revokeAll() async -> Bool {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/tokens/revoke_all.json", method: .POST
            )
            tokens.removeAll()
            return true
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}

struct SessionsView: View {
    @StateObject private var vm = SessionsViewModel()
    @EnvironmentObject private var auth: AuthManager
    @State private var showRevokeAll = false

    var body: some View {
        List {
            Section(footer: Text("撤销其他会话可保护账号安全；撤销当前会话会立即退出登录。")) {
                ForEach(vm.tokens, id: \.tokenId) { token in
                    HStack(spacing: 12) {
                        Image(systemName: tokenIcon(token))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(token.isCurrent ? Theme.brand : Color.gray))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(tokenTypeName(token)).font(.subheadline.weight(.medium))
                                if token.isCurrent {
                                    Text("当前")
                                        .font(.footnote)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Theme.brand.opacity(0.15))
                                        .foregroundColor(Theme.brand)
                                        .cornerRadius(6)
                                }
                            }
                            if let ua = token.userAgent, !ua.isEmpty {
                                Text(ua).font(.footnote).foregroundColor(.secondary).lineLimit(1)
                            }
                            Text("最近活跃 \(Self.relativeTime(token.lastSeen))")
                                .font(.footnote).foregroundColor(.secondary)
                        }
                        Spacer()
                        if !token.isCurrent {
                            Button {
                                Task { await vm.revoke(token) }
                            } label: {
                                Text("撤销").font(.footnote).foregroundColor(Theme.expense)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Button(role: .destructive) {
                    showRevokeAll = true
                } label: {
                    Text("撤销全部会话").frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("设备与会话")
        .refreshable { await vm.load() }
        .confirmationDialog("撤销全部会话？", isPresented: $showRevokeAll, titleVisibility: .visible) {
            Button("撤销全部", role: .destructive) {
                Task {
                    if await vm.revokeAll() { auth.logout() }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有设备（含当前设备）都会退出登录，需要重新登录。")
        }
        .task { await vm.load() }
    }

    private func tokenIcon(_ token: TokenInfo) -> String {
        switch token.tokenType {
        case 5: return "cpu"
        case 8: return "key"
        default: return "iphone"
        }
    }

    private func tokenTypeName(_ token: TokenInfo) -> String {
        switch token.tokenType {
        case 5: return "MCP 令牌"
        case 8: return "API 令牌"
        default: return "App / 浏览器会话"
        }
    }

    /// Unix 秒 → 相对时间（如「3 分钟前」）
    static func relativeTime(_ ts: Int64) -> String {
        guard ts > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
