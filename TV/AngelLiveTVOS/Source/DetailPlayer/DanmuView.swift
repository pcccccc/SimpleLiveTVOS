//
//  DanmuView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/5.
//

import SwiftUI
import UIKit
import AngelLiveCore

struct DanmuView: UIViewRepresentable {
    var coordinator: Coordinator
    var height: CGFloat
    @Environment(AppState.self) var appViewModel

    func makeUIView(context: Context) -> DanmakuView {
        let view = DanmakuView(frame: .init(x: 0, y: 0, width: 1920, height: height))
        // 各端统一采用顶部首个安全轨道;此处显式设置以固定 tvOS 行为。
        view.floatingTrackPolicy = .topPriority
        view.playingSpeed = Float(appViewModel.danmuSettingsViewModel.danmuSpeed)
        view.play()
        coordinator.uiView = view
        return view
    }

    func updateUIView(_ uiView: DanmakuView, context: Context) {
        // §6.1 切字号:仅当 frame 真变化时才重算轨道;paddingTop/trackHeight/displayArea 各自 didSet 已在真变化时重算
        let newFrame = CGRect(x: 0, y: 0, width: 1920, height: height)
        if uiView.frame != newFrame {
            uiView.frame = newFrame
            uiView.recalculateTracks()
        }
        uiView.paddingTop = 5
        uiView.trackHeight = CGFloat(Double(appViewModel.danmuSettingsViewModel.danmuFontSize) * 1.35)
        uiView.playingSpeed = Float(appViewModel.danmuSettingsViewModel.danmuSpeed)
        uiView.displayArea = 1
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var uiView: DanmakuView?

        func setup(view: DanmakuView) {
            self.uiView = view
        }

        /// 发射弹幕。共享工厂负责图文片段取图、局部降级、布局模型和样式。
        @MainActor
        func shoot(_ message: DanmakuDisplayMessage, showColorDanmu: Bool, alpha: CGFloat, font: CGFloat) {
            Task { @MainActor [weak self] in
                let model = await DanmakuDisplayModelFactory.makeModel(
                    for: message,
                    showColorDanmu: showColorDanmu,
                    alpha: alpha,
                    fontSize: font
                )
                self?.uiView?.shoot(danmaku: model)
            }
        }

        func pause() {
            DispatchQueue.main.async {
                self.uiView?.pause()
            }
        }

        func play() {
            DispatchQueue.main.async {
                self.uiView?.play()
            }
        }

        func clear() {
            DispatchQueue.main.async {
                self.uiView?.stop()
            }
        }
    }
}
