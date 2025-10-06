//
//  FavoriteService.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/19.
//

import Foundation
import CloudKit
import LiveParse

let roomId_colum_cloud = "room_id"
let userId_column_cloud = "user_id"
let userName_column_cloud = "user_name"
let roomTitle_column_cloud = "room_title"
let roomCover_column_cloud = "room_cover"
let userHeadImg_column_cloud = "user_head_img"
let liveType_column_cloud =  "live_type"
let liveState_column_cloud = "live_state"
let ck_identifier = "iCloud.icloud.dev.igod.simplelive"


class FavoriteService: NSObject {
    
    class func saveRecord(liveModel: LiveModel) async throws {
        let rec = CKRecord(recordType: "favorite_streamers")
        rec.setValue(liveModel.roomId, forKey: roomId_colum_cloud)
        rec.setValue(liveModel.userId, forKey: userId_column_cloud)
        rec.setValue(liveModel.userName, forKey: userName_column_cloud)
        rec.setValue(liveModel.roomTitle, forKey: roomTitle_column_cloud)
        rec.setValue(liveModel.roomCover, forKey: roomCover_column_cloud)
        rec.setValue(liveModel.userHeadImg, forKey: userHeadImg_column_cloud)
        rec.setValue(liveModel.liveType.rawValue, forKey: liveType_column_cloud)
        rec.setValue(liveModel.liveState ?? "", forKey: liveState_column_cloud)
        try await CKContainer(identifier: ck_identifier).privateCloudDatabase.save(rec)
    }
    
    class func searchRecord(roomId: String) async throws -> [LiveModel] {
        let container = CKContainer(identifier: ck_identifier)
        let database = container.privateCloudDatabase
        let predicate = NSPredicate(format: " \(roomId_colum_cloud) = '\(roomId)' ")
        let query = CKQuery(recordType: "favorite_streamers", predicate: predicate)
        // 使用新的 API
        let recordArray = try await database.records(matching: query)
        var temp: Array<LiveModel> = []
        for record in recordArray.matchResults.compactMap({ try? $0.1.get() }) {
            temp.append(LiveModel(userName: record.value(forKey: userName_column_cloud) as? String ?? "",
                                  roomTitle: record.value(forKey: roomTitle_column_cloud) as? String ?? "",
                                  roomCover: record.value(forKey: roomCover_column_cloud) as? String ?? "",
                                  userHeadImg: record.value(forKey: userHeadImg_column_cloud) as? String ?? "",
                                  liveType: LiveType(rawValue: record.value(forKey: liveType_column_cloud) as? String ?? "") ?? .bilibili,
                                  liveState: record.value(forKey: liveState_column_cloud) as? String ?? "",
                                  userId: record.value(forKey: userId_column_cloud) as? String ?? "",
                                  roomId: record.value(forKey: roomId_colum_cloud) as? String ?? "",
                                  liveWatchedCount: nil))
        }
        return temp
    }
    
    class func searchRecord() async throws -> [LiveModel] {
        let container = CKContainer(identifier: ck_identifier)
        let database = container.privateCloudDatabase
        let query = CKQuery(recordType: "favorite_streamers", predicate: NSPredicate(value: true))
        // 使用新的 API
        let recordArray = try await database.records(matching: query, resultsLimit: 99999)
        var temp: Array<LiveModel> = []
        for record in recordArray.matchResults.compactMap({ try? $0.1.get() }) {
            temp.append(LiveModel(userName: record.value(forKey: userName_column_cloud) as? String ?? "",
                                  roomTitle: record.value(forKey: roomTitle_column_cloud) as? String ?? "",
                                  roomCover: record.value(forKey: roomCover_column_cloud) as? String ?? "",
                                  userHeadImg: record.value(forKey: userHeadImg_column_cloud) as? String ?? "",
                                  liveType: LiveType(rawValue: record.value(forKey: liveType_column_cloud) as? String ?? "") ?? .bilibili,
                                  liveState: record.value(forKey: liveState_column_cloud) as? String ?? "",
                                  userId: record.value(forKey: userId_column_cloud) as? String ?? "",
                                  roomId: record.value(forKey: roomId_colum_cloud) as? String ?? "",
                                  liveWatchedCount: nil))
        }
        return temp
    }
    
    class func deleteRecord(liveModel: LiveModel) async throws {
        let container = CKContainer(identifier: ck_identifier)
        let database = container.privateCloudDatabase
        let predicate = NSPredicate(format: " \(roomId_colum_cloud) = '\(liveModel.roomId)' ")
        let query = CKQuery(recordType: "favorite_streamers", predicate: predicate)
        let recordArray = try await database.records(matching: query)
        if let firstRecord = recordArray.matchResults.first,
           let record = try? firstRecord.1.get() {
            try await database.deleteRecord(withID: record.recordID)
        }
    }
    
    class func getCloudState() async -> String {
        // 1. 检查 CloudKit 容器标识符
        guard !ck_identifier.isEmpty else {
            return "CloudKit 配置错误：容器标识符为空"
        }
        
        // 2. 检查 CloudKit 可用性
        guard CKContainer.default().containerIdentifier != nil else {
            return "CloudKit 服务不可用"
        }
        
        do {
            // 3. 使用更安全的容器初始化方式
            let container: CKContainer
            if ck_identifier == CKContainer.default().containerIdentifier {
                container = CKContainer.default()
            } else {
                container = CKContainer(identifier: ck_identifier)
            }
            
            // 4. 添加超时保护
            let status = try await withTimeout(seconds: 10) {
                try await container.accountStatus()
            }
            
            switch status {
                case .available:
                    return "正常"
                case .couldNotDetermine:
                    return "无法确定状态,请检查iCloud服务/网络连接是否正常"
                case .restricted:
                    return "iCloud用户受限"
                case .noAccount:
                    return "未登录iCloud，请进入 系统设置-用户和账户 登录Apple ID"
                case .temporarilyUnavailable:
                    return "iCloud服务不可用，请进入 系统设置-用户和账户 更新用户状态"
                @unknown default:
                    return "未知的iCloud状态"
            }
        } catch let error as CKError {
            return formatErrorCode(error: error)
        } catch is CancellationError {
            return "操作超时，请检查网络连接"
        } catch {
            // 5. 处理其他未预期的错误
            return "获取iCloud状态失败：\(error.localizedDescription)"
        }
    }
    
    // 添加超时保护的辅助方法
    private class func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            
            group.cancelAll()
            return result
        }
    }
    
    class func formatErrorCode(error: Error) -> String {
        guard let theError = error as? CKError else { return "未知错误" }
        switch theError.code {
            case .internalError:
                return "iCloud内部错误，请稍后再试"
            case .partialFailure, .networkUnavailable:
                return "网络不可用，请检查网络问题"
            case .badContainer:
                return "容器错误，请联系开发者"
            case .serviceUnavailable:
                return "CloudKit暂停服务，请稍后再试"
            case .requestRateLimited:
                return "操作频繁，请稍后再试"
            case .missingEntitlement:
                return "操作权限异常，请检查iCloud账户状态"
            case .notAuthenticated:
                return "未登录，请检查iCloud账户状态"
            case .permissionFailure:
                return "权限异常，请检查iCloud账户状态"
            case .unknownItem:
                return "操作记录不存在，请更新收藏列表"
            case .invalidArguments:
                return "错误请求，请更新收藏列表"
            case .serverRecordChanged:
                return "请求结果与iCloud不一致，请更新收藏列表"
            case .serverRejectedRequest:
                return "iCloud服务器拒绝了请求，请更新收藏列表"
            case .assetFileNotFound:
                return "文件未找到"
            case .assetFileModified:
                return "保存文件时文件被修改"
            case .incompatibleVersion:
                return "iCloud版本不兼容"
            case .constraintViolation:
                return "唯一字段冲突"
            case .operationCancelled:
                return "操作取消，请重试"
            case .changeTokenExpired:
                return "token异常，请重新登录Apple ID"
            case .batchRequestFailed:
                return "有其他线程访问，请稍后再试"
            case  .zoneBusy:
                return "iCloud服务器繁忙，请稍后再试"
            case .badDatabase:
                return "iCloud数据库异常"
            case .quotaExceeded:
                return "iCloud存储已满，请清理空间后再试"
            case .zoneNotFound:
                return "iCloud不存在此区域，请联系开发者"
            case .limitExceeded:
                return "对服务器的请求太大，请联系开发者"
            case .userDeletedZone:
                return "区域不存在"
            case .tooManyParticipants:
                return "同时操作用户多过，请稍后再试"
            case .alreadyShared:
                return "无法保存"
            case .referenceViolation:
                return "未找到共享区域"
            case .managedAccountRestricted:
                return "由于管理账户限制，请求被拒绝"
            case .accountTemporarilyUnavailable:
                return "账户暂时不可用，请尝试在系统设置中重新登录默认账户后再试"
            case .networkFailure:
                return "连接到iCloud失败，请检查网络"
            default:
                return "未知错误"
        }
    }
}
