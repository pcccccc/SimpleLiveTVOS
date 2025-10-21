//
//  LiveRoomCard.swift
//  AngelLive
//
//  Created by pangchong on 10/20/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct LiveRoomCard: View {
    let room: LiveModel
    @State private var isPressed = false
    @Namespace private var namespace

    init(room: LiveModel, width: CGFloat? = nil) {
        self.room = room
    }

    var body: some View {
        NavigationLink {
            DetailPlayerView()
                .environment(RoomInfoViewModel(room: room))
                .navigationTransition(.zoom(sourceID: room.roomId, in: namespace))
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
    }

    private var cardContent: some View {
        VStack {
            // 封面图
            ZStack(alignment: .center) {

                KFImage(URL(string: room.roomCover))
                    .placeholder {
                        Rectangle()
                            .fill(AppConstants.Colors.placeholderGradient())
                    }
                    .resizable()
                    .blur(radius: 10)
                    .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))

                KFImage(URL(string: room.roomCover))
                    .placeholder {
                        Image("placeholder")
                            .resizable()
                            .aspectRatio(AppConstants.AspectRatio.pic, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
                    }
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
            }
            .matchedTransitionSource(id: room.roomId, in: namespace)

            // 主播信息
            HStack(spacing: 8) {
                KFImage(URL(string: room.userHeadImg))
                    .placeholder {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(room.roomTitle)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppConstants.Colors.primaryText)
                        .lineLimit(1)

                    Text(room.userName)
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg)
                .fill(.clear)
        )
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3), value: isPressed)
        .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}
