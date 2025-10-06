//
//  GeneralSettingModel.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2024/9/21.
//

import Foundation
import SwiftUI
import Observation

enum AngelLiveFavoriteStyle: Int, CaseIterable, CustomStringConvertible {
    
    var description: String {
        switch self {
        case .normal:
            return "普通视图"
        case .section:
            return "按平台分组"
        case .liveState:
            return "按直播状态分组"
        }
    }
    
    case normal = 0
    case section = 1
    case liveState = 2
}

@Observable
final class GeneralSettingModel {
    
    static let globalGeneralDisableMaterialBackground = "SimpleLive.Setting.globalGeneralDisableMaterialBackground"
    static let globalGeneralSettingFavoriteStyle = "SimpleLive.Setting.favorite.style"
    
    @ObservationIgnored
    public var generalDisableMaterialBackground: Bool {
        get {
            access(keyPath: \.generalDisableMaterialBackground)
            return UserDefaults.shared.value(forKey: GeneralSettingModel.globalGeneralDisableMaterialBackground, synchronize: true) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.generalDisableMaterialBackground) {
                 UserDefaults.shared.set(newValue, forKey: GeneralSettingModel.globalGeneralDisableMaterialBackground, synchronize: true)
            }
        }
    }
    
    @ObservationIgnored
    public var globalGeneralSettingFavoriteStyle: Int {
        get {
            access(keyPath: \.globalGeneralSettingFavoriteStyle)
            return UserDefaults.shared.value(forKey: GeneralSettingModel.globalGeneralSettingFavoriteStyle, synchronize: true) as? Int ?? 0
        }
        set {
            withMutation(keyPath: \.globalGeneralSettingFavoriteStyle) {
                 UserDefaults.shared.set(newValue, forKey: GeneralSettingModel.globalGeneralSettingFavoriteStyle, synchronize: true)
            }
        }
    }
}
