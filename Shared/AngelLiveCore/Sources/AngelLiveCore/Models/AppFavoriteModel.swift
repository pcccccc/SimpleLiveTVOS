//
//  AppFavoriteModel.swift
//  AngelLiveCore
//
//  Created by pangchong on 10/17/25.
//

import Foundation
import SwiftUI
import CloudKit
import Observation
import LiveParse

/// iCloud同步状态
public enum CloudSyncStatus {
    case syncing      // 正在同步
    case success      // 同步成功
    case error        // 同步错误
    case notLoggedIn  // 未登录iCloud
}

@Observable
public final class AppFavoriteModel {
    public let actor = FavoriteStateModel()
    public var groupedRoomList: [FavoriteLiveSectionModel] = []
    public var roomList: [LiveModel] = []
    public var isLoading: Bool = false
    public var cloudKitReady: Bool = false
    public var cloudKitStateString: String = "正在检查iCloud状态"
    public var syncProgressInfo: (String, String, String, Int, Int) = ("", "", "", 0, 0)
    public var cloudReturnError = false
    public var syncStatus: CloudSyncStatus = .syncing
    public var lastSyncTime: Date?

    public init() {}

    /// 判断是否需要同步数据
    /// - Returns: 如果列表为空或距离上次同步超过1分钟则返回true
    public func shouldSync() -> Bool {
        // 如果列表为空，需要同步
        if roomList.isEmpty {
            return true
        }

        // 如果从未同步过，需要同步
        guard let lastSync = lastSyncTime else {
            return true
        }

        // 如果距离上次同步超过1分钟，需要同步
        let timeInterval = Date().timeIntervalSince(lastSync)
        return timeInterval > 60 // 60秒 = 1分钟
    }

    @MainActor
    public func syncWithActor() async {
        roomList.removeAll()
        groupedRoomList.removeAll()
        cloudReturnError = false
        syncProgressInfo = ("", "", "", 0, 0)
        self.isLoading = true
        self.syncStatus = .syncing

        let state = await actor.getState()
        self.cloudKitReady = state.0
        self.cloudKitStateString = state.1

        if self.cloudKitReady {
            do {
                let resp = try await actor.syncStreamerLiveStates()
                self.roomList = resp.0
                self.groupedRoomList = resp.1
                syncProgressInfo = ("", "", "", 0, 0)
                isLoading = false
                syncStatus = .success
                lastSyncTime = Date() // 记录同步时间
            } catch {
                self.cloudKitStateString = "获取收藏列表失败：" + FavoriteService.formatErrorCode(error: error)
                syncProgressInfo = ("", "", "", 0, 0)
                isLoading = false
                cloudReturnError = true
                syncStatus = .error
            }
        } else {
            let state = await FavoriteService.getCloudState()
            if state == "无法确定状态" {
                self.cloudKitStateString = "iCloud状态可能存在假登录，当前状态：" + state + "请尝试重新在设置中登录iCloud"
            } else {
                self.cloudKitStateString = state
            }
            syncProgressInfo = ("", "", "", 0, 0)
            isLoading = false
            cloudReturnError = true
            syncStatus = .notLoggedIn
        }
    }

    public func addFavorite(room: LiveModel) async throws {
        try await FavoriteService.saveRecord(liveModel: room)
        var favIndex = -1
        for (index, favoriteRoom) in roomList.enumerated() {
            if LiveState(rawValue: favoriteRoom.liveState ?? "3") != .live {
                favIndex = index
                break
            }
        }
        if favIndex != -1 {
            roomList.insert(room, at: favIndex)
        }
        roomList.append(room)
        if AngelLiveFavoriteStyle(rawValue: GeneralSettingModel().globalGeneralSettingFavoriteStyle) == .section {
            for (index, model) in groupedRoomList.enumerated() {
                if model.type == room.liveType {
                    groupedRoomList[index].roomList.append(room)
                    break
                }
            }
        }else {
            for (index, model) in groupedRoomList.enumerated() {
                if model.title == room.liveStateFormat() {
                    groupedRoomList[index].roomList.append(room)
                    break
                }
            }
        }
    }

    public func removeFavoriteRoom(room: LiveModel) async throws {
        try await FavoriteService.deleteRecord(liveModel: room)
        let index = roomList.firstIndex(of: room)
        if index != nil {
            self.roomList.remove(at: index!)
        }
        for (index, model) in groupedRoomList.enumerated() {
            if model.id == room.id {
                groupedRoomList.remove(at: index)
                break
            }
        }
        refreshView()
    }

    public func refreshView() {
        let theRoomList = roomList
        roomList.removeAll()
        roomList = theRoomList
        var groupedRoomList: [FavoriteLiveSectionModel] = []
        if AngelLiveFavoriteStyle(rawValue: GeneralSettingModel().globalGeneralSettingFavoriteStyle) == .section {
            let types = Set(roomList.map { $0.liveType })
            let formatedRoomList = types.map { type in
                roomList.filter { $0.liveType == type }
            }
            for array in formatedRoomList {
                let model = FavoriteLiveSectionModel()
                model.roomList = array
                model.title = LiveParseTools.getLivePlatformName(array.first?.liveType ?? .bilibili)
                model.type = array.first?.liveType ?? .bilibili
                groupedRoomList.append(model)
            }
            groupedRoomList = groupedRoomList.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            self.groupedRoomList = groupedRoomList
        }else {
            let types = Set(roomList.map { $0.liveState })
            let formatedRoomList = types.map { state in
                roomList.filter { $0.liveState == state }
            }
            for array in formatedRoomList {
                let model = FavoriteLiveSectionModel()
                model.roomList = array
                model.title = array.first?.liveStateFormat() ?? "未知状态"
                model.type = array.first?.liveType ?? .bilibili
                groupedRoomList.append(model)
            }
            groupedRoomList = groupedRoomList.sorted { model1, model2 in
                let order = ["正在直播", "回放/轮播", "已下播", "未知状态"]
                if let index1 = order.firstIndex(of: model1.title),
                   let index2 = order.firstIndex(of: model2.title) {
                    return index1 < index2
                }
                return model1.title < model2.title
            }
            self.groupedRoomList = groupedRoomList
        }
    }
}
