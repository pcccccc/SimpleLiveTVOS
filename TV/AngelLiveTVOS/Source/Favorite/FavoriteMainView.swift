//
//  FavoriteMainView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/11.
//

import SwiftUI
import Kingfisher
import SimpleToast
import LiveParse
import Shimmer

struct FavoriteMainView: View {
    
    @FocusState var focusState: Int?
    @Environment(LiveViewModel.self) var liveViewModel
    @Environment(AppState.self) var appViewModel
    @Environment(\.scenePhase) var scenePhase
    @State var timer: Timer?
    @State var second = 0
    @State var firstLoad = true
    
    var body: some View {
        
        @Bindable var appModel = appViewModel
        
        VStack {
            if appViewModel.favoriteViewModel.cloudKitReady {
                if appViewModel.favoriteViewModel.groupedRoomList.isEmpty && appViewModel.favoriteViewModel.isLoading == false {
                    if appViewModel.favoriteViewModel.roomList.isEmpty {
                        if appViewModel.favoriteViewModel.cloudReturnError {
                            Text(appViewModel.favoriteViewModel.cloudKitStateString)
                                .font(.title3)
                        }else {
                            Text("暂无收藏")
                                .font(.title3)
                        }
                    }else {
                        Text(appViewModel.favoriteViewModel.cloudKitStateString)
                            .font(.title3)
                        Button {
                            getViewStateAndFavoriteList()
                        } label: {
                            Label("刷新", systemImage: "arrow.counterclockwise")
                                .font(.headline.bold())
                        }
                    }
                }else {
                    ScrollView(.vertical) {
                        if AngelLiveFavoriteStyle(rawValue: appViewModel.generalSettingsViewModel.globalGeneralSettingFavoriteStyle) == .section || AngelLiveFavoriteStyle(rawValue: appViewModel.generalSettingsViewModel.globalGeneralSettingFavoriteStyle) == .liveState { //按平台分组展示页面
                            ForEach(appViewModel.favoriteViewModel.groupedRoomList, id: \.id) { section in
                                VStack {
                                    HStack {
                                        Text(section.title)
                                            .font(.title2.bold())
                                            .padding(.leading, 14)
                                        Spacer()
                                    }
                                    ScrollView(.horizontal) {
                                        LazyHGrid(rows: [GridItem(.fixed(370), spacing: 60, alignment: .leading)], spacing: 60) {
                                            ForEach(section.roomList.indices, id: \.self) { index in
                                                LiveCardView(index: index, currentLiveModel: section.roomList[index])
                                                    .environment(liveViewModel)
                                                    .environment(appViewModel)
                                                    .frame(width: 370, height: 240)
                                            }
                                            
                                        }
                                        .safeAreaPadding([.leading, .trailing], 25)
                                        .padding([.top, .bottom], 0)
                                    }
                                    .padding(.top, -45)
                                    Spacer()
                                }
                                .focusSection()
                            }
                            if appViewModel.favoriteViewModel.isLoading {
                                HStack{
                                    LoadingView()
                                        .frame(width: 370, height: 275)
                                        .cornerRadius(5)
                                        .shimmering(active: true)
                                        .redacted(reason: .placeholder)
                                    Spacer()
                                }
                            }
                        }else {
                            LazyVGrid(columns: [GridItem(.fixed(370), spacing: 60), GridItem(.fixed(370), spacing: 60), GridItem(.fixed(370), spacing: 60), GridItem(.fixed(370), spacing: 60)], spacing: 60) {
                                ForEach(appViewModel.favoriteViewModel.roomList.indices, id: \.self) { index in
                                    LiveCardView(index: index)
                                        .environment(liveViewModel)
                                        .environment(appViewModel)
                                        .frame(width: 370, height: 240)
                                }
                                if appViewModel.favoriteViewModel.isLoading {
                                    LoadingView()
                                        .frame(width: 370, height: 275)
                                        .cornerRadius(5)
                                        .shimmering(active: true)
                                        .redacted(reason: .placeholder)
                                }
                            }
                        }
                        
                    }
                }
            }else {
                Text(appViewModel.favoriteViewModel.cloudKitStateString)
                    .font(.title3)
                Button {
                    getViewStateAndFavoriteList()
                } label: {
                    Label("刷新", systemImage: "arrow.counterclockwise")
                        .font(.headline.bold())
                }
            }
        }
        .overlay {
            if appViewModel.favoriteViewModel.roomList.count > 0 && appViewModel.favoriteViewModel.cloudKitReady {
                VStack {
                    Spacer()
                    HStack {
                        ZStack {
                            HStack(spacing: 10) {
                                Image(systemName: "playpause.circle")
                                Text("刷新")
                            }
                            .frame(width: 190, height: 60)
                            .background(Color("hintBackgroundColor", bundle: .main).opacity(0.4))
                            .font(.callout.bold())
                            .cornerRadius(8)
                        }
                        .frame(width: 200, height: 100)
                        Spacer()
                    }
                }
            }
        }
        .simpleToast(isPresented: $appModel.favoriteViewModel.showToast, options: appViewModel.favoriteViewModel.toastOptions) {
            VStack(alignment: .leading) {
                Label("提示", systemImage: appModel.favoriteViewModel.toastTypeIsSuccess ? "checkmark.circle" : "xmark.circle")
                    .font(.headline.bold())
                Text(appModel.favoriteViewModel.toastTitle)
            }
            .padding()
            .background(.black.opacity(0.6))
            .foregroundColor(Color.white)
            .cornerRadius(10)
        }
        .onPlayPauseCommand(perform: {
            getViewStateAndFavoriteList()
        })
        .onReceive(NotificationCenter.default.publisher(for: SimpleLiveNotificationNames.favoriteRefresh)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: {
                getViewStateAndFavoriteList()
            })
        }
        .onChange(of: scenePhase) { oldValue, newValue in
            switch newValue {
                case .active:
                    
                    self.timer?.invalidate()
                    self.timer = nil
                    if second > 300 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: {
                            getViewStateAndFavoriteList()
                        })
                    }
                case .background:
                    print("background。。。。")
                case .inactive:
                    print("inactive。。。。")
                    startTimer()
                @unknown default:
                    break
            }
        }
        .onAppear {
            if firstLoad {
                getViewStateAndFavoriteList()
                firstLoad = false
            }
            appViewModel.favoriteViewModel.refreshView()
            if appViewModel.favoriteViewModel.cloudKitReady == true && appViewModel.favoriteViewModel.roomList.count > 0 {
                liveViewModel.roomList = appViewModel.favoriteViewModel.roomList
            }
        }
    }
}


//MARK: Events
extension FavoriteMainView {
    private func getViewStateAndFavoriteList() {
        Task {
            guard appViewModel.favoriteViewModel.isLoading == false else { return }
            await appViewModel.favoriteViewModel.syncWithActor()
            liveViewModel.roomList = appViewModel.favoriteViewModel.roomList
            self.second = 0
        }
    }
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            second += 1
        }
        timer?.fire()
    }
}
