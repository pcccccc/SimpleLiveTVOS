//
//  AdaptiveSearchView.swift
//  AngelLive
//
//  根据插件安装状态自适应显示搜索页或不可用提示。
//

import SwiftUI
import AngelLiveCore

struct AdaptiveSearchView: View {
    @Environment(PluginAvailabilityService.self) private var pluginAvailability

    var body: some View {
        if pluginAvailability.hasAvailablePlugins {
            SearchView()
                .apiCredentialContentIdentity()
        } else {
            EmptyView()
        }
    }
}
