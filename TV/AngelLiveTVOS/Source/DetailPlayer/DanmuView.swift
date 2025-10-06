//
//  DanmuView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/5.
//

import SwiftUI
import UIKit

struct DanmuView: UIViewRepresentable {
    var coordinator: Coordinator
    var height: CGFloat
    @Environment(AppState.self) var appViewModel

    func makeUIView(context: Context) -> DanmakuView {
        let view = DanmakuView(frame: .init(x: 0, y: 0, width: 1920, height: height))
        view.playingSpeed = 0.5
        view.play()
        coordinator.uiView = view
        return view
    }

    func updateUIView(_ uiView: DanmakuView, context: Context) {
        // 更新 UIView，如果有必要
        uiView.frame = .init(x: 0, y: 0, width: 1920, height: height)
        uiView.paddingTop = 5
        uiView.trackHeight = CGFloat(Double(appViewModel.danmuSettingsViewModel.danmuFontSize) * 1.35)
        uiView.displayArea = 1
        uiView.recalculateTracks()
        
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var uiView: DanmakuView?

        func setup(view: DanmakuView) {
            self.uiView = view
        }

        func shoot(text: String, showColorDanmu: Bool, color: UInt32, alpha: CGFloat, font: CGFloat) {
            let model = DanmakuTextCellModel(str: text, strFont: .systemFont(ofSize: font))
            if NSString(string: text).contains("醒目留言") {
    //            model.backgroundColor = UIColor(rgb: Int(color))
                model.backgroundColor = .orange
                model.color = .white
            }else {
                model.color = showColorDanmu ? UIColor(rgb: Int(color), alpha: alpha) : .white
            }
            DispatchQueue.main.async {
                self.uiView?.shoot(danmaku: model)
            }
        }
    }
}
