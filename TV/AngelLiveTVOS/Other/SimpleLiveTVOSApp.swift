//
//  SimpleLiveTVOSApp.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/6/26.
//

import SwiftUI
import LiveParse
import Bugsnag
import Kingfisher
import KingfisherWebP

@main
struct SimpleLiveTVOSApp: App {
    
    var appViewModel = AppState()
    
    init() {
        KingfisherManager.shared.defaultOptions += [
            .processor(WebPProcessor.default),
            .cacheSerializer(WebPSerializer.default)
        ]
        Bugsnag.start()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(appViewModel: appViewModel)
        }
    }
}

