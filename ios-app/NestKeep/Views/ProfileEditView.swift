import SwiftUI
import Combine
import UIKit

/// 用户资料：读取 / 更新（对齐 Web 的个人资料页）
@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: UserBasicInfo?
    @Published var accounts: [Account] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: String?
    @Published var didSave = false

    // 可编辑字段
    @Published var nickname = ""
    @Published var email = ""
    @Published var defaultAccountId = ""
    @Published var defaultCurrency = "CNY"
    @Published var firstDayOfWeek = 1
    @Published var fiscalYearStart = 1
    @Published var expenseAmountColor = 0
    @Published var incomeAmountColor = 0

    // 改密码
    @Published var oldPassword = ""
    @Published var newPassword = ""

    func load() async {
        isLoading = true
        error = nil
        do {
            async let profileResp: UserProfileResponse = APIClient.shared.request("/api/v1/users/profile/get.json")
            async let accs: [Account] = APIClient.shared.request("/api/v1/accounts/list.json")
            let p = try await profileResp
            accounts = (try? await accs) ?? []
            let basic = p.asBasicInfo
            profile = basic
            apply(basic)
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func apply(_ u: UserBasicInfo?) {
        guard let u = u else { return }
        nickname = u.nickname ?? ""
        email = u.email ?? ""
        defaultAccountId = u.defaultAccountId ?? ""
        defaultCurrency = u.defaultCurrency ?? "CNY"
        firstDayOfWeek = u.firstDayOfWeek ?? 1
        fiscalYearStart = u.fiscalYearStart ?? 1
        expenseAmountColor = u.expenseAmountColor ?? 0
        incomeAmountColor = u.incomeAmountColor ?? 0
    }

    func save() async {
        isSaving = true
        error = nil
        do {
            var req = UserProfileUpdateRequest()
            if !nickname.isEmpty { req.nickname = nickname }
            if !email.isEmpty { req.email = email }
            if !defaultAccountId.isEmpty { req.defaultAccountId = defaultAccountId }
            req.defaultCurrency = defaultCurrency
            req.firstDayOfWeek = firstDayOfWeek
            req.fiscalYearStart = fiscalYearStart
            req.expenseAmountColor = expenseAmountColor
            req.incomeAmountColor = incomeAmountColor

            // 改密码：需同时提供旧密码
            if !newPassword.isEmpty {
                req.oldPassword = oldPassword
                req.password = newPassword
            }

            let resp: UserProfileUpdateResponse = try await APIClient.shared.request(
                "/api/v1/users/profile/update.json", method: .POST, body: req
            )
            if let user = resp.user {
                await AuthManager.shared.updateCurrentUser(user, newToken: resp.newToken)
                profile = user
            }
            isSaving = false
            didSave = true
        } catch {
            isSaving = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct ProfileEditView: View {
    @StateObject private var vm = ProfileViewModel()
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var showAvatarDialog = false
    @State private var showAvatarPicker = false
    @State private var isUploadingAvatar = false
    @State private var avatarError: String?

    /// 头像展示地址（vm 与全局用户信息哪个有头像用哪个）
    private var avatarURL: URL? {
        AvatarUploader.displayURL(for: vm.profile?.avatar ?? auth.currentUser?.avatar)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Button {
                        showAvatarDialog = true
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            avatarView
                                .frame(width: 72, height: 72)
                                .clipShape(Circle())
                            Image(systemName: "camera.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(5)
                                .background(Circle().fill(Theme.brand))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploadingAvatar)

                    if isUploadingAvatar {
                        ProgressView()
                    } else {
                        Text("点击更换头像")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    if let avatarError = avatarError {
                        Text(avatarError)
                            .font(.footnote)
                            .foregroundColor(Theme.expense)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section(header: Text("账号")) {
                HStack {
                    Text("用户名")
                    Spacer()
                    Text(vm.profile?.username ?? "—").foregroundColor(.secondary)
                }
                TextField("昵称", text: $vm.nickname)
                TextField("邮箱", text: $vm.email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
            }

            Section(header: Text("偏好")) {
                Picker("默认账户", selection: $vm.defaultAccountId) {
                    Text("未设置").tag("")
                    ForEach(flattenedAccounts, id: \.id) { Text($0.name).tag($0.id) }
                }
                Picker("默认货币", selection: $vm.defaultCurrency) {
                    ForEach(UserProfileOptions.currencies, id: \.self) { Text($0).tag($0) }
                }
                Picker("每周首日", selection: $vm.firstDayOfWeek) {
                    ForEach(UserProfileOptions.weekDays, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("财年起始", selection: $vm.fiscalYearStart) {
                    ForEach(UserProfileOptions.fiscalYearStarts, id: \.0) { Text($0.1).tag($0.0) }
                }
            }

            Section(header: Text("金额颜色")) {
                Picker("支出", selection: $vm.expenseAmountColor) {
                    ForEach(UserProfileOptions.amountColors, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("收入", selection: $vm.incomeAmountColor) {
                    ForEach(UserProfileOptions.amountColors, id: \.0) { Text($0.1).tag($0.0) }
                }
            }

            Section(header: Text("修改密码"), footer: Text("不修改请留空")) {
                SecureField("当前密码", text: $vm.oldPassword)
                SecureField("新密码（至少 6 位）", text: $vm.newPassword)
            }

            if let error = vm.error {
                Section { Text(error).foregroundColor(.red).font(.footnote) }
            }
        }
        .navigationTitle("个人资料")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await vm.save() }
                } label: {
                    if vm.isSaving { ProgressView() } else { Text("保存").font(.body.weight(.semibold)) }
                }
                .disabled(vm.isSaving)
            }
        }
        .task { await vm.load() }
        .onChange(of: vm.didSave) { saved in if saved { dismiss() } }
        .confirmationDialog("头像", isPresented: $showAvatarDialog, titleVisibility: .visible) {
            Button("更换头像") { showAvatarPicker = true }
            if avatarURL != nil {
                Button("移除头像", role: .destructive) {
                    Task { await removeAvatar() }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showAvatarPicker) {
            PhotoPicker { data in
                Task { await uploadAvatar(data) }
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let url = avatarURL {
            CachedAsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Circle().fill(Theme.brand.opacity(0.12))
                    ProgressView()
                }
            }
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundColor(Theme.brand)
        }
    }

    private func uploadAvatar(_ data: Data) async {
        isUploadingAvatar = true
        avatarError = nil
        do {
            // 先解码再压到 ≤512px（服务端上限 1MB，原图直传必超）
            guard let image = UIImage(data: data), let payload = AvatarUploader.prepareData(image) else {
                throw APIError.invalidResponse
            }
            let user = try await AvatarUploader.upload(imageData: payload)
            vm.profile = user
            await AuthManager.shared.updateCurrentUser(user, newToken: nil)
        } catch {
            avatarError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isUploadingAvatar = false
    }

    private func removeAvatar() async {
        isUploadingAvatar = true
        avatarError = nil
        do {
            let user = try await AvatarUploader.remove()
            vm.profile = user
            await AuthManager.shared.updateCurrentUser(user, newToken: nil)
        } catch {
            avatarError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isUploadingAvatar = false
    }

    private var flattenedAccounts: [Account] {
        vm.accounts.flatMap { acc -> [Account] in
            var arr = [acc]
            if let subs = acc.subAccounts { arr.append(contentsOf: subs) }
            return arr
        }
    }
}
