import Foundation

public struct LiveParseDanmakuPlan: Decodable, Sendable {
    public let args: [String: String]
    public let headers: [String: String]?
    public let transport: LiveParseDanmakuTransportPlan?
    public let runtime: LiveParseDanmakuRuntimePlan?

    public init(
        args: [String: String],
        headers: [String: String]? = nil,
        transport: LiveParseDanmakuTransportPlan? = nil,
        runtime: LiveParseDanmakuRuntimePlan? = nil
    ) {
        self.args = args
        self.headers = headers
        self.transport = transport
        self.runtime = runtime
    }

    public var prefersHTTPPolling: Bool {
        if transport?.kind == .httpPolling {
            return true
        }
        return args["_danmu_type"]?.lowercased() == "http_polling"
    }

    public var usesPluginRuntimeDriver: Bool {
        runtime?.driver == .pluginJSV1
    }

    public var legacyParameters: [String: String] {
        var parameters = args

        if let transport {
            switch transport.kind {
            case .websocket:
                if let url = transport.url, !(parameters["ws_url"]?.isEmpty == false) {
                    parameters["ws_url"] = url
                }
                if let frameType = transport.frameType {
                    parameters["_ws_frame_type"] = frameType.rawValue
                }
                if let subprotocols = transport.subprotocols, !subprotocols.isEmpty {
                    parameters["_ws_subprotocols"] = subprotocols.joined(separator: ",")
                }
            case .httpPolling:
                parameters["_danmu_type"] = "http_polling"
                if let url = transport.url, !(parameters["_polling_url"]?.isEmpty == false) {
                    parameters["_polling_url"] = url
                }
                if let method = transport.polling?.method {
                    parameters["_polling_method"] = method
                }
                if let intervalMs = transport.polling?.intervalMs {
                    parameters["_polling_interval"] = String(intervalMs)
                }
                if let sendOnConnect = transport.polling?.sendOnConnect {
                    parameters["_polling_send_on_connect"] = sendOnConnect ? "true" : "false"
                }
            }
        }

        return parameters
    }

    public func updating(args: [String: String]) -> LiveParseDanmakuPlan {
        LiveParseDanmakuPlan(
            args: args,
            headers: headers,
            transport: transport,
            runtime: runtime
        )
    }
}

public struct LiveParseDanmakuTransportPlan: Decodable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        case websocket
        case httpPolling = "http_polling"
    }

    public enum FrameType: String, Decodable, Sendable {
        case text
        case binary
    }

    public let kind: Kind
    public let url: String?
    public let frameType: FrameType?
    public let subprotocols: [String]?
    public let polling: LiveParseDanmakuPollingPlan?

    public init(
        kind: Kind,
        url: String? = nil,
        frameType: FrameType? = nil,
        subprotocols: [String]? = nil,
        polling: LiveParseDanmakuPollingPlan? = nil
    ) {
        self.kind = kind
        self.url = url
        self.frameType = frameType
        self.subprotocols = subprotocols
        self.polling = polling
    }

    func dictionaryValue() -> [String: Any] {
        var payload: [String: Any] = ["kind": kind.rawValue]
        if let url, !url.isEmpty {
            payload["url"] = url
        }
        if let frameType {
            payload["frameType"] = frameType.rawValue
        }
        if let subprotocols, !subprotocols.isEmpty {
            payload["subprotocols"] = subprotocols
        }
        if let polling {
            payload["polling"] = polling.dictionaryValue()
        }
        return payload
    }
}

public struct LiveParseDanmakuPollingPlan: Decodable, Sendable {
    public let method: String?
    public let intervalMs: Int?
    public let sendOnConnect: Bool?

    public init(method: String? = nil, intervalMs: Int? = nil, sendOnConnect: Bool? = nil) {
        self.method = method
        self.intervalMs = intervalMs
        self.sendOnConnect = sendOnConnect
    }

    func dictionaryValue() -> [String: Any] {
        var payload: [String: Any] = [:]
        if let method, !method.isEmpty {
            payload["method"] = method
        }
        if let intervalMs {
            payload["intervalMs"] = intervalMs
        }
        if let sendOnConnect {
            payload["sendOnConnect"] = sendOnConnect
        }
        return payload
    }
}

public struct LiveParseDanmakuRuntimePlan: Decodable, Sendable {
    public enum Driver: String, Decodable, Sendable {
        case pluginJSV1 = "plugin_js_v1"
    }

    public enum WebSocketHeaderMode: String, Decodable, Sendable {
        case defaultHeaders = "default"
        case minimalNoCookie = "minimal_no_cookie"
    }

    public let driver: Driver
    public let protocolId: String?
    public let protocolVersion: String?
    public let webSocketHeaderMode: WebSocketHeaderMode?

    public init(
        driver: Driver,
        protocolId: String? = nil,
        protocolVersion: String? = nil,
        webSocketHeaderMode: WebSocketHeaderMode? = nil
    ) {
        self.driver = driver
        self.protocolId = protocolId
        self.protocolVersion = protocolVersion
        self.webSocketHeaderMode = webSocketHeaderMode
    }
}

struct LiveParseDanmakuDriverResult: Decodable, Sendable {
    let ok: Bool?
    let messages: [LiveParseDanmakuMessage]?
    let writes: [LiveParseDanmakuWriteAction]?
    let timer: LiveParseDanmakuTimerPlan?
    let poll: LiveParseDanmakuPollRequest?

    private enum CodingKeys: String, CodingKey {
        case ok, messages, writes, timer, poll
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
        writes = try container.decodeIfPresent([LiveParseDanmakuWriteAction].self, forKey: .writes)
        timer = try container.decodeIfPresent(LiveParseDanmakuTimerPlan.self, forKey: .timer)
        poll = try container.decodeIfPresent(LiveParseDanmakuPollRequest.self, forKey: .poll)
        // 逐条解码：单条消息格式异常时只丢这一条，其余消息照常送达。
        // 整数组一起解码会让一条坏消息带走整帧。
        messages = try container
            .decodeIfPresent([FailableDecodable<LiveParseDanmakuMessage>].self, forKey: .messages)?
            .compactMap(\.value)
    }
}

/// 逐元素容错解码包装：解码失败时 `value` 为 nil，不向外抛错。
struct FailableDecodable<Wrapped: Decodable & Sendable>: Decodable, Sendable {
    let value: Wrapped?

    init(from decoder: any Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

struct LiveParseDanmakuMessage: Decodable, Sendable {
    let text: String
    let nickname: String
    let color: UInt32?
    /// 可选块，存在即代表这是一条图片弹幕。是否为图片弹幕完全由插件判定。
    let image: LiveParseDanmakuImage?
    /// 有序图文片段。新插件优先输出此字段；缺失时继续使用旧的 text/image 字段。
    let segments: [LiveParseDanmakuSegment]?

    private enum CodingKeys: CodingKey {
        case text
        case nickname
        case color
        case image
        case segments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        nickname = try container.decode(String.self, forKey: .nickname)
        color = try container.decodeIfPresent(UInt32.self, forKey: .color)
        // 旧 image 块保持严格解码：字段类型错误时丢弃该消息，与既有行为一致。
        image = try container.decodeIfPresent(LiveParseDanmakuImage.self, forKey: .image)
        // segments 按片段容错：一个未来类型或畸形片段不应拖垮整条消息。
        segments = try container
            .decodeIfPresent([FailableDecodable<LiveParseDanmakuSegment>].self, forKey: .segments)?
            .compactMap(\.value)
    }
}

struct LiveParseDanmakuImage: Decodable, Sendable {
    let url: String
    let width: Double?
    let height: Double?
    let alt: String?
}

enum LiveParseDanmakuSegment: Decodable, Sendable {
    case text(String)
    case image(LiveParseDanmakuImage)

    private enum Kind: String, Decodable {
        case text
        case image
    }

    private enum CodingKeys: CodingKey {
        case type
        case text
        case url
        case width
        case height
        case alt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .image:
            self = .image(
                LiveParseDanmakuImage(
                    url: try container.decode(String.self, forKey: .url),
                    width: try container.decodeIfPresent(Double.self, forKey: .width),
                    height: try container.decodeIfPresent(Double.self, forKey: .height),
                    alt: try container.decodeIfPresent(String.self, forKey: .alt)
                )
            )
        }
    }
}

struct LiveParseDanmakuWriteAction: Decodable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case text
        case binary
    }

    let kind: Kind
    let text: String?
    let bytesBase64: String?
}

struct LiveParseDanmakuTimerPlan: Decodable, Sendable, Equatable {
    enum Mode: String, Decodable, Sendable {
        case off
        case heartbeat
        case polling
    }

    let mode: Mode
    let intervalMs: Int?
}

struct LiveParseDanmakuPollRequest: Decodable, Sendable {
    let url: String?
    let method: String?
    let headers: [String: String]?
    let query: [String: String]?
    let bodyText: String?
    let bodyBase64: String?
}
