//
//  DanmakuAsyncLayer.swift
//  DanmakuKit
//
//  Created by Q YiZhong on 2020/8/16.
//

import UIKit

class Sentinel {
    
    private var value: Int32 = 0
    
    public func getValue() -> Int32 {
        return value
    }
    
    public func increase() {
        let p = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        p.pointee = value
        OSAtomicIncrement32(p)
        p.deallocate()
    }
    
}

public class DanmakuAsyncLayer: CALayer {
    
    /// When true, it is drawn asynchronously and is ture by default.
    public var displayAsync = true
    
    public var willDisplay: ((_ layer: DanmakuAsyncLayer) -> Void)?
    
    public var displaying: ((_ context: CGContext, _ size: CGSize, _ isCancelled:(() -> Bool)) -> Void)?
    
    public var didDisplay: ((_ layer: DanmakuAsyncLayer, _ finished: Bool) -> Void)?
    
    /// The number of queues to draw the danmaku.
    public static var drawDanmakuQueueCount = 16 {
        didSet {
            guard drawDanmakuQueueCount != oldValue else { return }
            pool = nil
            createPoolIfNeed()
        }
    }
    
    private let sentinel = Sentinel()
    
    private static var pool: DanmakuQueuePool?
    
    override init() {
        super.init()
        contentsScale = UIScreen.main.scale
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    deinit {
        sentinel.increase()
    }
    
    public override func setNeedsDisplay() {
        //1. Cancel the last drawing
        sentinel.increase()
        //2. call super
        super.setNeedsDisplay()
    }
    
    public override func display() {
        display(isAsync: displayAsync)
    }
    
    private func display(isAsync: Bool) {
        guard displaying != nil else {
            willDisplay?(self)
            contents = nil
            didDisplay?(self, true)
            return
        }
        
        if isAsync {
            willDisplay?(self)
            let value = sentinel.getValue()
            let isCancelled = {() -> Bool in
                return value != self.sentinel.getValue()
            }
            let size = bounds.size
            let scale = contentsScale
            let opaque = isOpaque
            let backgroundColor = (opaque && self.backgroundColor != nil) ? self.backgroundColor : nil
            queue.async {
                guard !isCancelled() else { return }
                UIGraphicsBeginImageContextWithOptions(size, opaque, scale)
                guard let context = UIGraphicsGetCurrentContext() else {
                    UIGraphicsEndImageContext()
                    return
                }
                if opaque {
                    context.saveGState()
                    if backgroundColor == nil || (backgroundColor?.alpha ?? 0) < 1 {
                        context.setFillColor(UIColor.white.cgColor)
                        context.addRect(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
                        context.fillPath()
                    }
                    if let backgroundColor = backgroundColor {
                        context.setFillColor(backgroundColor)
                        context.addRect(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
                        context.fillPath()
                    }
                    context.restoreGState()
                }
                self.displaying?(context, size, isCancelled)
                if isCancelled() {
                    UIGraphicsEndImageContext()
                    DispatchQueue.main.async {
                        self.didDisplay?(self, false)
                    }
                    return
                }
                let image = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                if isCancelled() {
                    DispatchQueue.main.async {
                        self.didDisplay?(self, false)
                    }
                    return
                }
                DispatchQueue.main.async {
                    if isCancelled() {
                        self.didDisplay?(self, false)
                    } else {
                        self.contents = image?.cgImage
                        self.didDisplay?(self, true)
                    }
                }
            }
            
        } else {
            sentinel.increase()
            willDisplay?(self)
            UIGraphicsBeginImageContextWithOptions(bounds.size, isOpaque, contentsScale)
            guard let context = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return
            }
            displaying?(context, bounds.size, {() -> Bool in return false})
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            contents = image?.cgImage
            didDisplay?(self, true)
        }
    }
    
    private static func createPoolIfNeed() {
        guard DanmakuAsyncLayer.pool == nil else { return }
        DanmakuAsyncLayer.pool = DanmakuQueuePool(name: "com.DanmakuKit.DanmakuAsynclayer", queueCount: DanmakuAsyncLayer.drawDanmakuQueueCount, qos: .userInteractive)
    }
    
    private lazy var queue: DispatchQueue = {
        return DanmakuAsyncLayer.pool?.queue ?? DispatchQueue(label: "com.DanmakuKit.DanmakuAsynclayer")
    }()
    
}
