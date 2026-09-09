//
//  MacAccountManagementView.swift
//  AngelLiveMacOS
//
//  设置二级页:平台账号管理。展示已安装平台并跳转登录 sheet。
//

import SwiftUI
import AngelLiveCore

struct MacAccountManagementView: View {
    @ObservedObject private var syncService = PlatformCredentialSyncService.shared
    @Environment(PluginAvailabilityService.self) private var pluginAvailability

    @State private var platforms: [LoginPlatformEntry] = []
    @State private var methodSelection: LoginPlatformEntry?
    @State private var selectedLogin: LoginPresentation?
    @State private var accountSelection: LoginPlatformEntry?
    @State private var pendingMethodSelection: LoginPlatformEntry?
    @State private var openingAccount = false

    private struct LoginPresentation: Identifiable {
        let entry: LoginPlatformEntry
        let method: PlatformLoginMethod
        var id: String { "\(entry.pluginId):\(method.rawValue)" }
    }

    var body: some View {
        Form {
            Section {
                PanelHintCard(
                    title: "登录后自动同步会话",
                    message: "凭据由宿主安全保存，仅提供给对应插件用于登录验证和鉴权，不会与其他插件共享。",
                    systemImage: "person.crop.circle.badge.checkmark",
                    tint: .blue
                )
            }

            Section {
                if !pluginAvailability.hasAvailablePlugins {
                    ErrorView.empty(
                        title: "暂无已安装插件",
                        message: "请先在「插件管理」中安装平台扩展，安装完成后这里会显示对应平台。",
                        symbolName: "puzzlepiece.extension",
                        tint: .secondary,
                        layout: .compact(minHeight: 180)
                    )
                } else if platforms.isEmpty {
                    ErrorView.empty(
                        title: "当前插件未配置登录方式",
                        message: "已安装的插件没有声明可用的登录方式。",
                        symbolName: "person.crop.circle.badge.xmark",
                        tint: .secondary,
                        layout: .compact(minHeight: 180)
                    )
                } else {
                    ForEach(platforms) { entry in
                        platformAccountRow(entry)
                    }
                }
            } header: {
                Text("平台列表")
            } footer: {
                if !platforms.isEmpty {
                    Text("共 \(platforms.count) 个平台")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("账号管理")
        .task {
            await loadPlatforms()
            await syncService.refreshAllLoginStatus()
        }
        .sheet(item: $selectedLogin, onDismiss: {
            Task { await syncService.refreshAllLoginStatus() }
        }) { selection in
            MacPlatformLoginSheet(
                entry: selection.entry,
                method: selection.method
            )
                .frame(minWidth: 800, minHeight: 600)
        }
        .sheet(item: $accountSelection, onDismiss: {
            if let entry = pendingMethodSelection {
                pendingMethodSelection = nil
                selectLoginMethod(entry)
            }
        }) { entry in
            PlatformAPIAccountView(entry: entry) {
                pendingMethodSelection = entry
                accountSelection = nil
            }
            .frame(minWidth: 480, minHeight: 420)
        }
    }

    private func platformAccountRow(_ entry: LoginPlatformEntry) -> some View {
        Button {
            openingAccount = true
            Task {
                await openAccount(entry)
                openingAccount = false
            }
        } label: {
            PanelNavigationRow(
                title: entry.displayName,
                subtitle: loginMethodDescription(for: entry)
            ) {
                if let liveType = LiveType(rawValue: entry.liveType),
                   let icon = MacPlatformIconProvider.tabImage(for: liveType) {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } trailing: {
                if entry.supportsAPICredentials {
                    PlatformAPITokenStatusLabel(pluginId: entry.pluginId)
                } else {
                    loginStatusBadge(syncService.isLoggedIn(pluginId: entry.pluginId))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(openingAccount)
        .confirmationDialog("选择登录方式", isPresented: methodSelectionBinding(for: entry), titleVisibility: .visible) {
            ForEach(entry.methods(for: .macOS)) { method in
                Button(method == .deviceCode ? "登录 \(entry.displayName)" : method.title) {
                    selectedLogin = LoginPresentation(entry: entry, method: method)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(entry.displayName)
        }
    }

    private func methodSelectionBinding(for entry: LoginPlatformEntry) -> Binding<Bool> {
        Binding(
            get: { methodSelection?.pluginId == entry.pluginId },
            set: { if !$0 { methodSelection = nil } }
        )
    }

    private func openAccount(_ entry: LoginPlatformEntry) async {
        if entry.supportsAPICredentials {
            let service = PlatformAPITokenService.shared
            await service.load(pluginId: entry.pluginId)
            if service.statuses[entry.pluginId] != nil || service.failures[entry.pluginId] != nil {
                accountSelection = entry
                return
            }
        }
        if syncService.isLoggedIn(pluginId: entry.pluginId) {
            selectedLogin = LoginPresentation(entry: entry, method: .web)
            return
        }
        selectLoginMethod(entry)
    }

    private func selectLoginMethod(_ entry: LoginPlatformEntry) {
        let methods = entry.methods(for: .macOS)
        if methods.count > 1 {
            methodSelection = entry
        } else if let method = methods.first {
            selectedLogin = LoginPresentation(entry: entry, method: method)
        }
    }

    private func loadPlatforms() async {
        let all = await PlatformLoginRegistry.shared.availablePlatforms()
        platforms = all.filter { pluginAvailability.isPluginInstalled(for: $0.pluginId) }
    }

    private func loginMethodDescription(for entry: LoginPlatformEntry) -> String {
        entry.methods(for: .macOS).map(\.title).joined(separator: " / ")
    }

    private func loginStatusBadge(_ isLoggedIn: Bool) -> some View {
        PanelStatusBadge(isLoggedIn ? "已登录" : "未登录", tint: isLoggedIn ? AppConstants.Colors.success : .secondary)
    }
}
