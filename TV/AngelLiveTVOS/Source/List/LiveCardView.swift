//
//  LiveCardView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/9.
//

import SwiftUI
import Kingfisher
import KSPlayer
import LiveParse
import Observation
import KingfisherWebP

struct LiveCardView: View {
    
    @Environment(LiveViewModel.self) var liveViewModel
    @Environment(AppState.self) var appViewModel
    @State var index: Int
    @State var currentLiveModel: LiveModel?
    @State private var isLive: Bool = false
    @FocusState var focusState: FocusableField?

    let cardGradient = LinearGradient(stops: [
        .init(color: .black.opacity(0.5), location: 0.0),
        .init(color: .black.opacity(0.25), location: 0.45),
        .init(color: .black.opacity(0), location: 0.8)
    ], startPoint: .bottom, endPoint: .top)
    
    var body: some View {
        
        @Bindable var liveModel = liveViewModel
        @State var roomList = liveViewModel.roomList
        
        if index < roomList.count {
            let currentLiveModel = self.currentLiveModel == nil ? roomList[index] : self.currentLiveModel!
            VStack(alignment: .leading, spacing: 10, content: {
                ZStack(alignment: Alignment(horizontal: .leading, vertical: .top), content: {
                    Button {
                        enterDetailRoom()
                    } label: {
                        ZStack(alignment: .bottom) {
                            KFImage(URL(string: currentLiveModel.roomCover))
                                .placeholder {
                                    Image("placeholder")
                                        .resizable()
                                        .frame(height: 210)
                                }
                                .resizable()
                                .frame(height: 210)
                                .blur(radius: 10)
                            KFImage(URL(string: currentLiveModel.roomCover))
                                .onFailure { error in
                                    print("Image loading failed: \(error)")
                                }
                                .placeholder {
                                    Image("placeholder")
                                        .resizable()
                                        .frame(height: 210)
                                }
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 210)
                                .background(.thinMaterial)
                                
                            Rectangle()
                            .fill(cardGradient)
                            .shadow(radius: 10)
                            .frame(height: 40)
                            if currentLiveModel.liveWatchedCount != nil {
                                HStack {
                                    Spacer()
                                    HStack(spacing: 5) {
                                        Image(systemName: "eye")
                                            .font(.system(size: 14))
                                        Text(currentLiveModel.liveWatchedCount!.formatWatchedCount())
                                            .font(.system(size: 18))
                                    }
                                    
                                    .foregroundColor(.white)
                                    .padding([.trailing], 10)
                                }
                                .frame(height: 30, alignment: .trailing)
                            }
                            if liveViewModel.roomListType != .live { // 如果不为直播页面，则展示对应平台和直播状态
                                HStack {
                                    Image(uiImage: .init(named: getImage())!)
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .cornerRadius(5)
                                        .padding(.top, 5)
                                        .padding(.leading, 5)
                                    Spacer()
                                    HStack(spacing: 5) {
                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(formatLiveStateColor())
                                                .frame(width: 10, height: 10)
                                                .padding(.leading, 5)
                                            Text(currentLiveModel.liveStateFormat())
                                                .font(.system(size: 18))
                                                .foregroundColor(Color.white)
                                                .padding(.trailing, 5)
                                                .padding(.top, 5)
                                                .padding(.bottom, 5)
                                        }
                                        .background(Color("favorite_right_hint"))
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                    }
                                    .padding(.trailing, 5)
                                }
                                .task {
                                    do {
                                        try await refreshStateIfStateIsUnknow()
                                    }catch {
                                        // todo
                                    }
                                }
                                .padding(.bottom, 165)
                            }
                        }
                    }
                    .buttonStyle(.card)
                    .focused($focusState, equals: .mainContent(index))
                    .onChange(of: focusState, { oldValue, newValue in
                        liveViewModel.currentRoom = liveViewModel.roomList[index]
                        liveViewModel.selectedRoomListIndex = index
                        if liveViewModel.roomListType != .history {
                            switch newValue {
                                case .mainContent(let index):
                                    liveViewModel.selectedRoomListIndex = index
                                    if liveViewModel.roomListType == .live || liveViewModel.roomListType == .search  {
                                        if index >= liveViewModel.roomList.count - 4 && liveModel.roomListType != .favorite { //如果小于4 就尝试刷新。
                                            liveViewModel.roomPage += 1
                                        }
                                    }
                                default: break
                            }
                        }
                    })

                    .alert("提示", isPresented: $liveModel.showAlert) {
                        Button("取消收藏", role: .destructive, action: {
                            Task {
                                do {
                                    try await appViewModel.favoriteViewModel.removeFavoriteRoom(room: liveViewModel.currentRoom!)
                                    liveViewModel.showToast(true, title:"取消收藏成功")
                                }catch {
                                    liveViewModel.showToast(false, title:FavoriteService.formatErrorCode(error: error))
                                }
                            }
                        })
                        Button("再想想",role: .cancel) {
                            liveViewModel.showAlert = false
                        }
                    } message: {
                        Text("确认取消收藏吗")
                    }
                    .contextMenu(menuItems: {
                        if liveViewModel.currentRoomIsFavorited {
                            Button(action: {
                                Task {
                                    do {
                                        try await appViewModel.favoriteViewModel.removeFavoriteRoom(room: liveViewModel.currentRoom!)
                                        appViewModel.favoriteViewModel.roomList.removeAll(where: { $0.roomId == liveViewModel.currentRoom!.roomId })
                                        liveViewModel.showToast(true, title:"取消收藏成功")
                                        liveViewModel.currentRoomIsFavorited = false
                                    }catch {
                                        liveViewModel.showToast(false, title:FavoriteService.formatErrorCode(error: error))
                                    }
                                }
                            }, label: {
                                HStack {
                                    Image(systemName: "heart.fill")
                                    Text("取消收藏")
                                }
                            })
                            
                        }else {
                            Button(action: {
                                Task {
                                    do {
                                        if liveViewModel.currentRoom!.liveState == nil || (liveViewModel.currentRoom!.liveState ?? "").isEmpty || liveViewModel.currentRoom!.liveState == "" {
                                            liveViewModel.currentRoom!.liveState = try await ApiManager.getCurrentRoomLiveState(roomId: liveViewModel.currentRoom!.roomId, userId: liveViewModel.currentRoom!.userId, liveType: liveViewModel.currentRoom!.liveType).rawValue
                                        }
                                        try await appViewModel.favoriteViewModel.addFavorite(room: liveViewModel.currentRoom!)
                                        liveViewModel.showToast(true, title:"收藏成功")
                                        appViewModel.favoriteViewModel.roomList.append(liveViewModel.currentRoom!)
                                        liveViewModel.currentRoomIsFavorited = true
                                    }catch {
                                        liveViewModel.showToast(false, title:FavoriteService.formatErrorCode(error: error))
                                    }
                                }
                            }, label: {
                                HStack {
                                    Image(systemName: "heart.fill")
                                    Text("收藏")
                                }
                            })
                        }
                        if liveViewModel.roomListType == .history {
                            Button(action: {
                                liveViewModel.deleteHistory(index: index)
                            }, label: {
                                HStack {
                                    Image(systemName: "trash.circle")
                                    Text("删除")
                                }
                            })
                        }
                    })
                    .fullScreenCover(isPresented: $isLive, content: {
                        if liveViewModel.roomInfoViewModel != nil {
                            DetailPlayerView { isLive, hint in
                                self.isLive = isLive
                            }
                            .environment(liveViewModel.roomInfoViewModel!)
                            .environment(appViewModel)
                            .edgesIgnoringSafeArea(.all)
                            .frame(width: 1920, height: 1080)
                        }
                    })
                })
                HStack(spacing: 15) {
                    KFImage(URL(string: currentLiveModel.userHeadImg))
                        .resizable()
                        .frame(width: 40, height: 40)
                        .cornerRadius(20)
                    VStack (alignment: .leading, spacing: 5) {
                        Text(currentLiveModel.userName)
                            .font(.system(size: 22).weight(.semibold))
                        Text(currentLiveModel.roomTitle)
                            .font(.system(size: 16))
                    }
                    Spacer()
                }
                .padding(.top, focusState == .mainContent(index) ? 25 : 10)
                .scaleEffect(focusState == .mainContent(index) ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.25), value: focusState == .mainContent(index))
                .frame(height: 50)
            })
        }
        
    }
    
    private func enterDetailRoom() {
        liveViewModel.currentRoom = currentLiveModel ?? liveViewModel.roomList[index]
        liveViewModel.selectedRoomListIndex = index
        if LiveState(rawValue: self.liveViewModel.currentRoom?.liveState ?? "unknow") == .live || ((self.liveViewModel.currentRoom?.liveType == .huya || self.liveViewModel.currentRoom?.liveType == .douyu) && LiveState(rawValue: self.liveViewModel.currentRoom?.liveState ?? "unknow") == .video) || self.liveViewModel.roomListType == .live {
            if appViewModel.historyViewModel.watchList.contains(where: { self.liveViewModel.currentRoom!.roomId == $0.roomId }) == false {
                appViewModel.historyViewModel.watchList.insert(self.liveViewModel.currentRoom!, at: 0)
            }
            var enterFromLive = false
            if liveViewModel.roomListType == .live {
                enterFromLive = true
            }
            liveViewModel.createCurrentRoomViewModel(enterFromLive: enterFromLive)
            DispatchQueue.main.async {
                isLive = true
            }
        }else {
            DispatchQueue.main.async {
                isLive = false
                liveViewModel.showToast(false, title: "主播已经下播")
            }
        }
    }
    
    func formatLiveStateColor() -> Color {
        let currentLiveModel = self.currentLiveModel == nil ? liveViewModel.roomList[index] : self.currentLiveModel!
        if LiveState(rawValue: currentLiveModel.liveState ?? "3") == .live || LiveState(rawValue:currentLiveModel.liveState ?? "3") == .video {
            return Color.green
        }else {
            return Color.gray
        }
    }
    
    func refreshStateIfStateIsUnknow() async throws {
        guard index < liveViewModel.roomList.count else { return }

        let currentLiveModel: LiveModel
        if let existingModel = self.currentLiveModel {
            currentLiveModel = existingModel
        } else {
            currentLiveModel = liveViewModel.roomList[index]
        }

        if currentLiveModel.liveState == "" {
            let newState = try await ApiManager.getCurrentRoomLiveState(roomId: currentLiveModel.roomId, userId: currentLiveModel.userId, liveType: currentLiveModel.liveType)
            await MainActor.run {
                self.currentLiveModel?.liveState = newState.rawValue
            }
        }
    }

    func getImage() -> String {
        guard index < liveViewModel.roomList.count else { return "live_card_bili" }

        let currentLiveModel: LiveModel
        if let existingModel = self.currentLiveModel {
            currentLiveModel = existingModel
        } else {
            currentLiveModel = liveViewModel.roomList[index]
        }

        switch currentLiveModel.liveType {
            case .bilibili:
                return "live_card_bili"
            case .douyu:
                return "live_card_douyu"
            case .huya:
                return "live_card_huya"
            case .douyin:
                return "live_card_douyin"
            case .yy:
                return "live_card_yy"
            case .cc:
                return "live_card_cc"
            case .ks:
                return "live_card_ks"
            case .youtube:
                return "live_card_youtube"
        }
    }
}
