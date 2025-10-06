//
//  ApiManager.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/12/29.
//

import Foundation
import LiveParse
import Alamofire

class ApiManager {
    /**
     获取当前房间直播状态。
     
     - Returns: 直播状态
    */
    class func getCurrentRoomLiveState(roomId: String, userId: String?, liveType: LiveType) async throws -> LiveState {
        switch liveType {
            case .bilibili:
                return try await Bilibili.getLiveState(roomId: roomId, userId: nil)
            case .huya:
                return try await Huya.getLiveState(roomId: roomId, userId: nil)
            case .douyin:
                return try await Douyin.getLiveState(roomId: roomId, userId: userId)
            case .douyu:
                return try await Douyu.getLiveState(roomId: roomId, userId: nil)
            case .cc:
                return try await NeteaseCC.getLiveState(roomId: roomId, userId: userId)
            case .ks:
                return try await KuaiShou.getLiveState(roomId: roomId, userId: userId)
            case .yy:
                return try await YY.getLiveState(roomId: roomId, userId: userId)
            default:
                return .unknow
        }
    }

    class func fetchRoomList(liveCategory: LiveCategoryModel, page: Int, liveType: LiveType) async throws -> [LiveModel] {
        switch liveType {
            case .bilibili:
                return try await Bilibili.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: page)
            case .huya:
                return try await Huya.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: page)
            case .douyin:
                return try await Douyin.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: page)
            case .douyu:
                return try await Douyu.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: page)
            case .cc:
                return try await NeteaseCC.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: page)
            case .ks:
                return try await KuaiShou.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: page)
            case .yy:
                return try await YY.getRoomList(id: liveCategory.id, parentId: liveCategory.parentId, page: page)
            default:
                return []
        }
    }

    class func fetchCategoryList(liveType: LiveType) async throws -> [LiveMainListModel] {
        switch liveType {
            case .bilibili:
                return try await Bilibili.getCategoryList()
            case .huya:
                return try await Huya.getCategoryList()
            case .douyin:
                return try await Douyin.getCategoryList()
            case .douyu:
                return try await Douyu.getCategoryList()
            case .cc:
                return try await NeteaseCC.getCategoryList()
            case .ks:
                return try await KuaiShou.getCategoryList()
            case .yy:
                return try await YY.getCategoryList()
            default:
                return []
        }
    }
    
    class func fetchLastestLiveInfo(liveModel: LiveModel) async throws -> LiveModel {
        switch liveModel.liveType {
            case .bilibili:
                return try await Bilibili.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
            case .huya:
                return try await Huya.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
            case .douyin:
                return try await Douyin.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
            case .douyu:
                return try await Douyu.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
            case .cc:
                return try await NeteaseCC.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
            case .ks:
                return try await KuaiShou.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
            case .yy:
                return try await YY.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
            case .youtube:
                return try await YoutubeParse.getLiveLastestInfo(roomId: liveModel.roomId, userId: liveModel.userId)
        }
    }
    
    class func fetchSearchWithShareCode(shareCode: String) async throws -> LiveModel? {

        // 确定平台类型
        let platform: LiveType? = {
            if shareCode.contains("b23.tv") || shareCode.contains("bilibili") { return .bilibili }
            if shareCode.contains("douyin") { return .douyin }
            if shareCode.contains("huya") { return .huya }
            if shareCode.contains("hy.fan") { return .huya }
            if shareCode.contains("douyu") { return .douyu }
            if shareCode.contains("cc.163.com") { return .cc }
            if shareCode.contains("kuaishou.com") { return .ks }
            if shareCode.contains("yy.com") { return .yy }
            if shareCode.contains("youtube") { return .youtube }
            return nil
        }()
        
        if let platform = platform {
            // 已知平台的处理
            return try await handlePlatformSearch(shareCode, platform: platform)
        } else {
            // 未知平台
            throw NSError(domain: "解析房间号失败，请检查分享码/分享链接是否正确", code: -10000, userInfo: ["desc": "解析房间号失败，请检查分享码/分享链接是否正确"])
        }
    }
    
    private class func handlePlatformSearch(_ text: String, platform: LiveType) async throws -> LiveModel? {
        switch platform {
        case .bilibili:
            return try await Bilibili.getRoomInfoFromShareCode(shareCode: text)
        case .douyin:
            let room = try await Douyin.getRoomInfoFromShareCode(shareCode: text)
            let liveState = try await Douyin.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
            return LiveModel(userName: room.userName, roomTitle: room.roomTitle,
                            roomCover: room.roomCover, userHeadImg: room.userHeadImg,
                            liveType: room.liveType, liveState: liveState,
                            userId: room.userId, roomId: room.roomId,
                            liveWatchedCount: room.liveWatchedCount)
        case .huya:
            return try await Huya.getRoomInfoFromShareCode(shareCode: text)
        case .douyu:
            let room = try await Douyu.getRoomInfoFromShareCode(shareCode: text)
            let liveState = try await Douyu.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
            return LiveModel(userName: room.userName, roomTitle: room.roomTitle,
                            roomCover: room.roomCover, userHeadImg: room.userHeadImg,
                            liveType: room.liveType, liveState: liveState,
                            userId: room.userId, roomId: room.roomId,
                            liveWatchedCount: room.liveWatchedCount)
        case .cc:
            let room = try await NeteaseCC.getRoomInfoFromShareCode(shareCode: text)
            let liveState = try await NeteaseCC.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
            return LiveModel(userName: room.userName, roomTitle: room.roomTitle,
                            roomCover: room.roomCover, userHeadImg: room.userHeadImg,
                            liveType: room.liveType, liveState: liveState,
                            userId: room.userId, roomId: room.roomId,
                            liveWatchedCount: room.liveWatchedCount)
        case .ks:
            let room = try await KuaiShou.getRoomInfoFromShareCode(shareCode: text)
            let liveState = try await KuaiShou.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
            return LiveModel(userName: room.userName, roomTitle: room.roomTitle,
                            roomCover: room.roomCover, userHeadImg: room.userHeadImg,
                            liveType: room.liveType, liveState: liveState,
                            userId: room.userId, roomId: room.roomId,
                            liveWatchedCount: room.liveWatchedCount)
        case .yy:
            let room = try await YY.getRoomInfoFromShareCode(shareCode: text)
            let liveState = try await YY.getLiveState(roomId: room.roomId, userId: room.userId).rawValue
            return LiveModel(userName: room.userName, roomTitle: room.roomTitle,
                            roomCover: room.roomCover, userHeadImg: room.userHeadImg,
                            liveType: room.liveType, liveState: liveState,
                            userId: room.userId, roomId: room.roomId,
                            liveWatchedCount: room.liveWatchedCount)
        case .youtube:
            return try await YoutubeParse.getRoomInfoFromShareCode(shareCode: text)
        }
    }

    /**
     获取用户是否可以访问google。
     
     - Returns: 是否
    */
    class func checkInternetConnection() async -> Bool {
        let url = URL(string: "https://www.google.com")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let resp = response as? HTTPURLResponse else {
                return false
            }
            if resp.statusCode == 200 {
                return true
            }else {
                return false
            }
        }catch {
            return false
        }
    }
}
