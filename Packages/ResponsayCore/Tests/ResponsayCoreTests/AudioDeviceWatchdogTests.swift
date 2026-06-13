import Testing
import Foundation
@testable import ResponsayCore

@Suite struct AudioDeviceWatchdogTests {
    @Test func normalOperationDoesNotFire() async throws {
        let fired = ManagedAtomic(false)
        let watchdog = AudioDeviceWatchdog(
            firstCallbackDeadline: 0.5,
            interCallbackDeadline: 0.3,
            onTimeout: { fired.store(true) })
        watchdog.start()
        // Ping faster than inter-callback deadline
        for _ in 0..<5 {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            watchdog.ping()
        }
        watchdog.stop()
        #expect(!fired.load())
    }

    @Test func firstCallbackTimeoutFires() async throws {
        let fired = ManagedAtomic(false)
        let watchdog = AudioDeviceWatchdog(
            firstCallbackDeadline: 0.3,
            interCallbackDeadline: 5.0,
            onTimeout: { fired.store(true) })
        watchdog.start()
        // Never ping — first callback deadline should fire
        try await Task.sleep(nanoseconds: 600_000_000) // 0.6s
        #expect(fired.load())
        watchdog.stop()
    }

    @Test func interCallbackTimeoutFires() async throws {
        let fired = ManagedAtomic(false)
        let watchdog = AudioDeviceWatchdog(
            firstCallbackDeadline: 5.0,
            interCallbackDeadline: 0.3,
            onTimeout: { fired.store(true) })
        watchdog.start()
        watchdog.ping() // arm the inter-callback path
        // Stop pinging — inter-callback deadline should fire
        try await Task.sleep(nanoseconds: 600_000_000) // 0.6s
        #expect(fired.load())
        watchdog.stop()
    }

    @Test func stopPreventsTimeout() async throws {
        let fired = ManagedAtomic(false)
        let watchdog = AudioDeviceWatchdog(
            firstCallbackDeadline: 0.3,
            interCallbackDeadline: 0.3,
            onTimeout: { fired.store(true) })
        watchdog.start()
        watchdog.stop()
        try await Task.sleep(nanoseconds: 600_000_000) // 0.6s
        #expect(!fired.load())
    }

    @Test func firesExactlyOnce() async throws {
        let count = ManagedAtomic(0)
        let watchdog = AudioDeviceWatchdog(
            firstCallbackDeadline: 0.2,
            interCallbackDeadline: 0.2,
            onTimeout: { count.add(1) })
        watchdog.start()
        try await Task.sleep(nanoseconds: 800_000_000) // 0.8s — well past deadline
        #expect(count.load() == 1)
        watchdog.stop()
    }

    @Test func concurrentPingAndStopDoesNotReviveStoppedWatchdog() async throws {
        let count = ManagedAtomic(0)
        let watchdog = AudioDeviceWatchdog(
            firstCallbackDeadline: 0.2,
            interCallbackDeadline: 0.2,
            onTimeout: { count.add(1) })
        watchdog.start()

        DispatchQueue.concurrentPerform(iterations: 128) { index in
            if index.isMultiple(of: 4) {
                watchdog.stop()
            } else {
                watchdog.ping()
            }
        }

        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s — past both deadlines
        #expect(count.load() == 0)
    }

    @Test func stopRacingTimeoutNeverFiresMoreThanOnce() async throws {
        for _ in 0..<40 {
            let count = ManagedAtomic(0)
            let watchdog = AudioDeviceWatchdog(
                firstCallbackDeadline: 0.02,
                interCallbackDeadline: 0.02,
                onTimeout: {
                    count.add(1)
                    Thread.sleep(forTimeInterval: 0.002)
                })
            watchdog.start()

            try await Task.sleep(nanoseconds: 18_000_000) // land near the first timeout edge
            DispatchQueue.concurrentPerform(iterations: 16) { _ in
                watchdog.stop()
            }
            try await Task.sleep(nanoseconds: 40_000_000)
            #expect(count.load() <= 1)
        }
    }
}

/// Lock-backed atomic for test assertions from multiple threads.
private final class ManagedAtomic<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) { self.value = value }

    func load() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func store(_ newValue: T) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

extension ManagedAtomic where T == Int {
    func add(_ delta: Int) {
        lock.lock()
        value += delta
        lock.unlock()
    }
}
