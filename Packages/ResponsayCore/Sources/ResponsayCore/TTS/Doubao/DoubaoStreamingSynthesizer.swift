import Foundation

/// Bridge connecting the DoubaoBiTTSClient to the app's `StreamingSpeechSynthesizer` protocol.
///
/// Sends the text in a single burst (TaskRequest) and streams back the 24kHz PCM chunks
/// natively into `SynthesizedSpeech` float arrays.
public struct DoubaoStreamingSynthesizer: StreamingSpeechSynthesizer {
    public let credentials: DoubaoTTSCredentials
    public let voice: String
    
    public init(credentials: DoubaoTTSCredentials, voice: String) {
        self.credentials = credentials
        self.voice = voice
    }
    
    public func stream(_ text: String, speed: Double) -> AsyncThrowingStream<SynthesizedSpeech, Error> {
        let textToSpeak = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return AsyncThrowingStream { continuation in
            guard !textToSpeak.isEmpty else {
                continuation.finish(throwing: TTSError.emptyText)
                return
            }
            
            let client = DoubaoBiTTSClient(credentials: credentials)
            
            Task {
                do {
                    // 1. Open Session
                    try await client.openSession(voice: voice, speed: speed)
                    
                    // 2. Send Text
                    try await client.sendText(textToSpeak, voice: voice)
                    
                    // 3. Send Finish
                    try await client.finishSession()
                    
                    // 4. Stream Audio
                    for try await data in client.audioStream {
                        let samples = pcm16ToFloat(data)
                        if !samples.isEmpty {
                            let chunk = SynthesizedSpeech(samples: samples, sampleRate: 24_000)
                            continuation.yield(chunk)
                        }
                    }
                    
                    continuation.finish()
                } catch let error as DoubaoBiTTSError {
                    switch error {
                    case .credentialsMissing:
                        continuation.finish(throwing: TTSError.missingAPIKey(provider: "Doubao"))
                    case .authRejected(let status):
                        continuation.finish(throwing: TTSError.http(status: status))
                    case .connectionFailed(let msg):
                        continuation.finish(throwing: TTSError.network(msg))
                    default:
                        continuation.finish(throwing: TTSError.synthesisFailed(error.localizedDescription))
                    }
                } catch {
                    continuation.finish(throwing: TTSError.synthesisFailed(error.localizedDescription))
                }
            }
        }
    }
    
    private func pcm16ToFloat(_ data: Data) -> [Float] {
        let count = data.count / 2
        var samples = [Float](repeating: 0.0, count: count)
        data.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<count {
                samples[i] = Float(Int16(littleEndian: int16Buffer[i])) / 32768.0
            }
        }
        return samples
    }
}
