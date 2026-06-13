import Foundation

/// Detects mic disconnect or audio tap silence.
///
/// Two deadlines: `firstCallbackDeadline` (time from start to first audio
/// callback) and `interCallbackDeadline` (max gap between consecutive
/// callbacks). When either fires, the `onTimeout` closure runs exactly once.
///
/// The watchdog does NOT listen for `AVAudioEngineConfigurationChange`
/// itself — that notification is main-thread / NotificationCenter, which
/// belongs in the macOS capture-service layer. This type is the timer-based
/// fallback (pure Foundation, testable without AVFoundation).
public final class AudioDeviceWatchdog: @unchecked Sendable {
    private let firstCallbackDeadline: TimeInterval
    private let interCallbackDeadline: TimeInterval
    private let onTimeout: @Sendable () -> Void
    private let lock = NSLock()
    private var lastCallbackTime: CFAbsoluteTime = 0
    private var hasReceivedCallback = false
    private var fired = false
    private var timer: DispatchSourceTimer?
    private var generation: UInt64 = 0

    public init(
        firstCallbackDeadline: TimeInterval = 5.0,
        interCallbackDeadline: TimeInterval = 3.0,
        onTimeout: @escaping @Sendable () -> Void
    ) {
        self.firstCallbackDeadline = firstCallbackDeadline
        self.interCallbackDeadline = interCallbackDeadline
        self.onTimeout = onTimeout
    }

    /// Call once after `engine.start()` to arm the watchdog.
    public func start() {
        let interval = min(firstCallbackDeadline, interCallbackDeadline) / 3.0
        let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        source.schedule(deadline: .now() + interval, repeating: interval)

        lock.lock()
        let previousTimer = timer
        generation &+= 1
        let currentGeneration = generation
        lastCallbackTime = CFAbsoluteTimeGetCurrent()
        hasReceivedCallback = false
        fired = false
        timer = source
        lock.unlock()

        source.setEventHandler { [weak self] in self?.check(generation: currentGeneration) }
        previousTimer?.cancel()
        source.resume()
    }

    /// Call from the audio tap callback to reset the watchdog.
    public func ping() {
        lock.lock()
        guard !fired else {
            lock.unlock()
            return
        }
        lastCallbackTime = CFAbsoluteTimeGetCurrent()
        hasReceivedCallback = true
        lock.unlock()
    }

    /// Disarm the watchdog. Safe to call multiple times.
    public func stop() {
        lock.lock()
        let source = timer
        timer = nil
        fired = true
        lock.unlock()
        source?.cancel()
    }

    private func check(generation expectedGeneration: UInt64) {
        let shouldFire: Bool
        let sourceToCancel: DispatchSourceTimer?

        lock.lock()
        guard !fired, generation == expectedGeneration else {
            lock.unlock()
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastCallbackTime
        let deadline = hasReceivedCallback ? interCallbackDeadline : firstCallbackDeadline
        shouldFire = elapsed >= deadline
        if shouldFire {
            fired = true
            sourceToCancel = timer
            timer = nil
        } else {
            sourceToCancel = nil
        }
        lock.unlock()

        if shouldFire {
            sourceToCancel?.cancel()
            onTimeout()
        }
    }
}
