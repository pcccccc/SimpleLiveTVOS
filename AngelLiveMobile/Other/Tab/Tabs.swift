//
//  Tabs.swift
//  AngelLiveMobile
//
//  Created by pc on 2024/9/4.
//

import SwiftUI

enum Tabs: Equatable, Hashable, Identifiable {
    case favorite
    case platform
    case platformSection
    case setting
    case search
    
    
    var id: Int {
        switch self {
            case .favorite:
                7000
            case .platform:
                7001
            case .setting:
                7002
            case .search:
                7003
            case .platformSection:
                7004
        }
    }
    
    var name: String {
        switch self {
            case .favorite:
                "收藏"
            case .platform:
                "平台"
            case .setting:
                "设置"
            case .search:
                "搜索"
            case .platformSection:
                "平台列表"
        }
    }
    
    var customizationID: String {
        return "AngelLive.Tab." + self.name
    }
    
    var symbol: String {
        switch self {
            case .favorite:
                "heart.text.square.fill"
            case .platform:
                "list.bullet"
            case .setting:
                "gear"
            case .search:
                "magnifyingglass"
            case .platformSection:
                "list.bullet"
        }
    }
    
    var isSecondary: Bool {
        switch self {
            case .favorite, .setting, .search, .platform:
                false
            case .platformSection:
                true
        }
    }
}

