//
//  ListCardView.swift
//  AngelLiveMobile
//
//  Created by pc on 2024/9/11.
//

import SwiftUI
import Kingfisher
import AngelLiveTools

struct ListCardView: View {
    
    @Environment(LiveListViewModel.self) var liveListViewModel
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        GeometryReader { geometry in
            
            let itemWidth = Common.calcPadItemCounts(width: geometry.size.width, horizontalSizeClass: horizontalSizeClass)
            RefreshableScrollView(content: {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(itemWidth.0), spacing: 15), count: itemWidth.1), alignment: .leading, spacing: 15) {
                    ForEach(liveListViewModel.roomList, id: \.id) { item in
                        NavigationLink {
                            
                        } label: {
                            VStack {
                                KFImage(.init(string: item.roomCover))
                                    .placeholder {
                                        Image("placeholder")
                                            .resizable()
                                            .cornerRadius(5)
                                    }
                                    .resizable()
                                    .frame(width: itemWidth.0, height: itemWidth.0 * 0.6)
                                    .cornerRadius(5)

                                HStack(alignment: .top) {
                                    
                                    KFImage(.init(string: item.userHeadImg))
                                        .placeholder {
                                            AnyView(Color.gray)
                                                .cornerRadius(15)
                                        }
                                        .resizable()
                                        .cornerRadius(15)
                                        .frame(width: 30, height: 30)
                                    
                                    VStack(alignment: .leading) {
                                        Text(item.roomTitle)
                                            .fontWeight(.bold)
                                            .lineLimit(2)
                                            .lineSpacing(5)
                                            .truncationMode(.tail)
                                            .multilineTextAlignment(.leading)
                                        Text(item.userName)
                                            .fontWeight(.medium)
                                    }
                                    
                                    Spacer()
                                }
                                
                                Spacer()
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.leading, 30)
                .padding(.top, 30)
            
            }, onRefresh: {
                liveListViewModel.getRoomList(index: liveListViewModel.selectedSubListIndex)
            }, onLoadMore: {
                
            })
        }

        .onAppear {
            
        }
    }
}

//#Preview {
//    ListCardView()
//}