import Foundation

/// NOTE: there are deliberately no punctuation/ITN/timestamp switches here —
/// the server ignores the legacy NLS-style parameters and keeps all of them
/// permanently on (live A/B verified 2026-06-11, issue 286). Faithful-profile
/// "no punctuation" is NOT achievable on this engine.
public struct FunASRRealtimeEndpoint: Sendable, Equatable {
    public var model: String
    public var region: QwenRealtimeRegion
    public var sampleRate: Int

    public init(
        model: String = "fun-asr-realtime",
        region: QwenRealtimeRegion = .china,
        sampleRate: Int = 16000
    ) {
        self.model = model
        self.region = region
        self.sampleRate = sampleRate
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = region.host
        components.path = "/api-ws/v1/inference"
        return components.url!
    }
}
