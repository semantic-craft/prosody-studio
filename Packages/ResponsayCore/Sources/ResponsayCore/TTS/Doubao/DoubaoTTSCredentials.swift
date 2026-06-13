import Foundation

/// Credentials for Volcengine Doubao TTS V3.
///
/// Responsay deliberately uses the legacy speech-console auth shape here so
/// Doubao TTS matches the Volcengine ASR configuration path.
public struct DoubaoTTSCredentials: Sendable, Equatable {
    public static let defaultResourceID = "seed-tts-2.0"
    public static let bidirectionalEndpoint = "wss://openspeech.bytedance.com/api/v3/tts/bidirection"

    public var appId: String
    public var accessToken: String
    public var resourceID: String
    public var endpoint: String

    public init(
        appId: String,
        accessToken: String,
        resourceID: String = Self.defaultResourceID,
        endpoint: String = Self.bidirectionalEndpoint
    ) {
        self.appId = appId
        self.accessToken = accessToken
        self.resourceID = resourceID
        self.endpoint = endpoint
    }

    public var isComplete: Bool {
        return !resourceID.trimmed.isEmpty
            && !appId.trimmed.isEmpty
            && !accessToken.trimmed.isEmpty
    }

    var trimmedEndpoint: String {
        endpoint.trimmed.isEmpty ? Self.bidirectionalEndpoint : endpoint.trimmed
    }

    func authHeaders(connectID: String) -> [String: String] {
        [
            "X-Api-App-Id": appId.trimmed,
            "X-Api-Access-Key": accessToken.trimmed,
            "X-Api-Resource-Id": resourceID.trimmed.isEmpty ? Self.defaultResourceID : resourceID.trimmed,
            "X-Api-Connect-Id": connectID,
        ]
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
