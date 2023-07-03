//
//  ContentView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/6/26.
//

import SwiftUI
import Kingfisher

struct ContentView: View {
    @State var size: CGFloat = 100.0
    var body: some View {
//        VStack {
//            Image(systemName: "globe")
//                .imageScale(.large)
//                .foregroundColor(.accentColor)
//            Text("Hello, world!")
//        }
//        .padding()
        TabView {
            HStack {
                menu(size: $size)
                    .cornerRadius(20)
                VStack(alignment: .leading, content: {
                    
                    ScrollView([.horizontal]) {
                        LazyHGrid(rows: [GridItem()]) {
                            ForEach(["1", "2", "3", "4" , "5", "6"], id: \.self) { playlist in
                                Button(action: goToPlaylist) {
                                    
                                    VStack {
                                        KFImage(URL(string: "http://i0.hdslb.com/bfs/live/504185f422f2fc9422fd22b61cf5d2b6d5cb439e.jpg"))
        //                                    .resizable()
                                            .frame(width: 320, height: 180)
                                        Text("英雄联盟")
                                            .background(Color.clear)
                                    }
                                }
                                .buttonStyle(CardButtonStyle())
                                .padding(.leading, 25)
                            }
                        }
                    }
                   
                    ScrollView([.horizontal]) {
                        LazyHGrid(rows: [GridItem()]) {
                            ForEach(["1", "2", "3", "4" , "5", "6"], id: \.self) { playlist in
                                Button(action: goToPlaylist) {
                                    
                                    VStack {
                                        KFImage(URL(string: "http://i0.hdslb.com/bfs/live/504185f422f2fc9422fd22b61cf5d2b6d5cb439e.jpg"))
        //                                    .resizable()
                                            .frame(width: 320, height: 180)
                                        Text("英雄联盟")
                                            .background(Color.clear)
                                    }
                                }
                                .buttonStyle(CardButtonStyle())
                                .padding(.leading, 25)
                            }
                        }
                    }
          
                    ScrollView([.horizontal]) {
                        LazyHGrid(rows: [GridItem()]) {
                            ForEach(["1", "2", "3", "4" , "5", "6"], id: \.self) { playlist in
                                Button(action: goToPlaylist) {
                                    
                                    VStack {
                                        KFImage(URL(string: "http://i0.hdslb.com/bfs/live/504185f422f2fc9422fd22b61cf5d2b6d5cb439e.jpg"))
        //                                    .resizable()
                                            .frame(width: 320, height: 180)
                                        Text("英雄联盟")
                                            .background(Color.clear)
                                            .padding(.bottom, 5)
                                    }
                                }
                                .contextMenu(menuItems: {
                                    Button {
                                        
                                    } label: {
                                        Text("收藏")
                                    }
                                    Button {
                                        
                                    } label: {
                                        Text("取消")
                                    }
                                })
                                .buttonStyle(CardButtonStyle())
                                .padding(.leading, 25)
                            }
                        }
                    }
                })
            }
            .tabItem {
                Label("收藏", systemImage: "heart.fill")
            }
            ZStack {
                
            }
            .tabItem {
                Label("bilibi", image: "bilibili")
            }
            ZStack {
                
            }
            .tabItem {
                Label("虎牙", image: "huya")
            }
            ZStack {
                
            }
            .tabItem {
                Label("斗鱼", image: "douyu")
            }
            ZStack {
                
            }
            .tabItem {
                Label("企鹅", image: "egame")
            }
            ZStack {
                
            }
            .tabItem {
                Label("抖音", image: "douyin")
            }
        }
    }
    
    func goToPlaylist() {
        
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct menu : View {
    @Binding var size : CGFloat
    @State var leftMenuIsFocusedArray: Array<Bool> = [false, false, false, false, false]
    
    var body : some View{
        VStack{
            HStack{
                Button(action: {

                }) {
                    LeftMenuButton(index: 0 ,doSomething: { index, isFocused in
                        self.showOrHide(index: index, isFocused: isFocused)
                    })
                }
                .buttonStyle(CardButtonStyle())
            }
            HStack{
                Button(action: {

                }) {
                    LeftMenuButton(index: 1 ,doSomething: { index, isFocused in
                        self.showOrHide(index: index, isFocused: isFocused)
                    })
                }
                .buttonStyle(CardButtonStyle())
            }
            HStack{
                Button(action: {

                }) {
                    LeftMenuButton(index: 2 ,doSomething: { index, isFocused in
                        self.showOrHide(index: index, isFocused: isFocused)
                    })
                }
                .buttonStyle(CardButtonStyle())
            }
            HStack{
                Button(action: {

                }) {
                    LeftMenuButton(index: 3 ,doSomething: { index, isFocused in
                        
                        self.showOrHide(index: index, isFocused: isFocused)
                    })
                }
                .buttonStyle(CardButtonStyle())
            }

            HStack{
                Button(action: {

                }) {
                    LeftMenuButton(index: 4 ,doSomething: { index, isFocused in
                        self.showOrHide(index: index, isFocused: isFocused)
                    })
                }
                .buttonStyle(CardButtonStyle())
            }
            Spacer()
        }
        .frame(width: self.size)
        .padding(.top, 30)

        // if u want to change swipe menu background color
    }
    
    func showOrHide(index: Int ,isFocused: Bool) {
        withAnimation {
            self.leftMenuIsFocusedArray[index] = isFocused
            var flag = 0
            for itemFocused in self.leftMenuIsFocusedArray {
                if itemFocused == true {
                    self.size = 300
                    flag = 1
                    break
                }
            }
            if flag == 0 {
                self.size = 100
            }
        }
    }
}

struct LeftMenuButton: View {
    
    @Environment(\.isFocused) private var isFocused : Bool
    var index: Int
    var doSomething: (Int, Bool) -> Void = { _,_  in }
    
    var body: some View {
        HStack {
            Image("bilibili")
                .frame(width: 30, height: 30)
            if isFocused {
                Text(isFocused ? "英雄联盟2": "英雄联盟")
            }
        }
        .onChange(of: isFocused) { newValue in
            
            self.doSomething(index, newValue)
        }
    }
}

