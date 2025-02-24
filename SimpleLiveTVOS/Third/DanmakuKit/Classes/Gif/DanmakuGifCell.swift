//
//  DanmakuGifCell.swift
//  DanmakuKit
//
//  Created by Q YiZhong on 2021/8/30.
//

import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

/// You can use or inherit this cell to shoot a danmaku with a GIF animation.
/// You need to implement the DanmakuGifCellModel protocol for your data source.
/// And specify that the cellClass generated by the data source is DanmakuGifCell or a subclass derived from it.
/// This is a subclass that only shows GIF capabilities.
/// If you want to implement other specific features, you can refer to the implementation of this class.
open class DanmakuGifCell: DanmakuCell {
    
    private var gifModel: DanmakuGifCellModel? {
        return model as? DanmakuGifCellModel
    }
    
    public private(set) var animator: GifAnimator?
    
    public required init(frame: CGRect) {
        super.init(frame: frame)
        displayAsync = false
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    open override func enterTrack() {
        super.enterTrack()
        prepare()
        animator?.startAnimation()
    }
    
    open override func leaveTrack() {
        super.leaveTrack()
        animator?.stopAnimation()
        animator = nil
    }
    
    private func prepare() {
        animator = nil
        guard let gifModel = gifModel else { return }
        guard let data = gifModel.resource else { return }
        guard let image = UIImage(data: data) else {
            debugPrint("Could not create gif animetion because image create failed.")
            return
        }
        
        let info: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceTypeIdentifierHint: UTType.gif
        ]
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, info as CFDictionary) else {
            debugPrint("Could not create gif animetion because imageSource create failed.")
            return
        }
        
        let animator = GifAnimator(imageSource: imageSource,
                                   preloadCount: gifModel.preloadFrameCount,
                                   imageSize: gifModel.size,
                                   imageScale: image.scale,
                                   maxRepeatCount: gifModel.maxRepeatCount)
        animator.backgroundDecode = gifModel.backgroundDecode
        animator.prepare()
        animator.update = { [weak self] in
            guard let frame = $0 else { return }
            self?.layer.contents = frame.cgImage
        }
        self.animator = animator
    }
    
}

