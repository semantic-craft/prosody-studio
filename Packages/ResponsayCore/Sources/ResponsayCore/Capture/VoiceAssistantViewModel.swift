import Foundation
import Observation

public struct VoiceAssistantMessage: Identifiable, Sendable {
    public let id = UUID()
    public let role: String
    public let content: String
    
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

@MainActor
@Observable
public final class VoiceAssistantViewModel {
    public enum Phase {
        case idle
        case listening
        case thinking
        case responding
    }
    
    public private(set) var phase: Phase = .idle
    public private(set) var messages: [VoiceAssistantMessage] = []
    public private(set) var partialTranscript: String = ""
    public private(set) var level: Float = 0
    public private(set) var errorMessage: String?
    
    private let speech: SpeechCaptureService
    private var levelTask: Task<Void, Never>?
    private var partialTask: Task<Void, Never>?
    private var responseTask: Task<Void, Never>?
    
    public init(speech: SpeechCaptureService) {
        self.speech = speech
    }
    
    public func startCapture() {
        guard phase == .idle || phase == .responding else { return }
        errorMessage = nil
        partialTranscript = ""
        phase = .listening
        
        do {
            try speech.start(locale: .chinese)
            startLevelMonitoring()
            startPartialMonitoring()
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }
    
    public func stopCapture(client: DirectStreamingChatClient?) async {
        guard phase == .listening else { return }
        phase = .thinking
        
        stopMonitoring()
        do {
            let finalTranscript = try await speech.stop()
            if finalTranscript.isEmpty {
                phase = .idle
                return
            }
            messages.append(VoiceAssistantMessage(role: "user", content: finalTranscript))
            
            await streamResponse(client: client)
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }
    
    private func streamResponse(client: DirectStreamingChatClient?) async {
        guard let client = client else {
            errorMessage = "LLM 不可用。请在「设置」中配置通用大模型。"
            phase = .idle
            return
        }
        
        phase = .responding
        
        var apiMessages = [["role": "system", "content": "You are a helpful and concise voice assistant."]]
        for msg in messages {
            apiMessages.append(["role": msg.role, "content": msg.content])
        }
        
        messages.append(VoiceAssistantMessage(role: "assistant", content: ""))
        let assistantIndex = messages.count - 1
        
        responseTask?.cancel()
        responseTask = Task {
            do {
                let stream = client.stream(messages: apiMessages)
                for try await event in stream {
                    if Task.isCancelled { break }
                    switch event {
                    case .delta(let token):
                        let current = self.messages[assistantIndex].content
                        self.messages[assistantIndex] = VoiceAssistantMessage(role: "assistant", content: current + token)
                    case .done:
                        break
                    case .failed(let err):
                        self.errorMessage = err
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    public func clearConversation() {
        responseTask?.cancel()
        messages.removeAll()
        partialTranscript = ""
        errorMessage = nil
        phase = .idle
    }
    
    private func startLevelMonitoring() {
        levelTask?.cancel()
        levelTask = Task {
            for await lvl in speech.levels {
                if Task.isCancelled { break }
                self.level = lvl
            }
        }
    }
    
    private func startPartialMonitoring() {
        partialTask?.cancel()
        guard let provider = speech as? SpeechPartialTranscriptProviding else { return }
        partialTask = Task {
            for await txt in provider.partialTranscripts {
                if Task.isCancelled { break }
                self.partialTranscript = txt
            }
        }
    }
    
    private func stopMonitoring() {
        levelTask?.cancel()
        partialTask?.cancel()
        level = 0
    }
}
