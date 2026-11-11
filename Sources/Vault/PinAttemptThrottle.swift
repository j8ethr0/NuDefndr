// NuDefndr - nudefndr.com
// Transparency Repository - PIN attempt throttle (v2.6.8)

import Foundation
import os

enum PinAttemptThrottle {
    private static let keychainAccount = "com.dro1d.PicDefndr.pinAttemptState"

    private static let freeAttempts = 3
    private static let ladder: [TimeInterval] = [30, 60, 300, 900, 3600]

    private struct State: Codable {
        var consecutiveFailures: Int
        var lockedUntil: Date?
        var lockedAtMonotonic: TimeInterval?
        var lockDuration: TimeInterval?
        var bootID: String?
    }

    private static func monotonicSeconds() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }

    private static var bootIdentifier: String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func remainingLockout(now: Date = Date()) -> TimeInterval? {
        let state: State
        switch read() {
        case .none:
            return nil
        case .state(let stored):
            state = stored
        case .unreadable(let corrupt):
            if corrupt {
                failureLock.withLock {
                    if case .unreadable(corrupt: true) = read() {
                        save(lockedState(failures: freeAttempts + 1, now: now))
                    }
                }
                return ladder[0]
            }
            let since = unreadableSince.withLock { since in
                if since == nil { since = now }
                return since!
            }
            let remaining = ladder[0] - now.timeIntervalSince(since)
            return remaining > 0 ? remaining : nil
        }
        guard let until = state.lockedUntil else { return nil }
        let remaining: TimeInterval
        if let bootID = state.bootID, bootID == bootIdentifier,
           let began = state.lockedAtMonotonic, let duration = state.lockDuration,
           monotonicSeconds() >= began {
            remaining = duration - (monotonicSeconds() - began)
        } else {
            remaining = until.timeIntervalSince(now)
        }
        return remaining > 0 ? remaining : nil
    }

    static var isLockedOut: Bool { remainingLockout() != nil }

    static var consecutiveFailures: Int {
        switch read() {
        case .none: return 0
        case .state(let state): return state.consecutiveFailures
        case .unreadable: return freeAttempts
        }
    }

    @discardableResult
    static func recordFailure(now: Date = Date()) -> TimeInterval? {
        let outcome: (failures: Int, delay: TimeInterval)? = failureLock.withLock {
            var state: State
            switch read() {
            case .none: state = State(consecutiveFailures: 0)
            case .state(let stored): state = stored
            case .unreadable: state = State(consecutiveFailures: freeAttempts)
            }
            state.consecutiveFailures += 1

            let over = state.consecutiveFailures - freeAttempts
            guard over > 0 else {
                state.lockedUntil = nil
                state.lockedAtMonotonic = nil
                state.lockDuration = nil
                state.bootID = nil
                save(state)
                return nil
            }

            let delay = ladder[min(over - 1, ladder.count - 1)]
            state = lockedState(failures: state.consecutiveFailures, now: now)
            save(state)
            return (state.consecutiveFailures, delay)
        }
        guard let outcome else { return nil }

        AppLogger.security.notice("PIN throttle: \(outcome.failures, privacy: .public) consecutive failures, locked for \(Int(outcome.delay), privacy: .public)s")
        AuditLogManager.shared.log(
            .authFailed,
            message: "PIN entry throttled after repeated failures",
            metadata: ["consecutive_failures": "\(outcome.failures)",
                       "lockout_seconds": "\(Int(outcome.delay))"]
        )
        return outcome.delay
    }

    static func recordSuccess() {
        clear()
    }

    @discardableResult
    static func clear() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func lockedState(failures: Int, now: Date) -> State {
        let delay = ladder[min(max(failures - freeAttempts, 1) - 1, ladder.count - 1)]
        return State(consecutiveFailures: failures,
                     lockedUntil: now.addingTimeInterval(delay),
                     lockedAtMonotonic: monotonicSeconds(),
                     lockDuration: delay,
                     bootID: bootIdentifier)
    }

    private static let unreadableSince = OSAllocatedUnfairLock<Date?>(initialState: nil)

    private static let failureLock = NSLock()

    private enum Stored {
        case none
        case state(State)
        case unreadable(corrupt: Bool)
    }

    private static func read() -> Stored {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound {
            unreadableSince.withLock { $0 = nil }
            return .none
        }
        guard status == errSecSuccess, let data = out as? Data else {
            AppLogger.security.error("PIN throttle state unreadable (status: \(status, privacy: .public))")
            return .unreadable(corrupt: false)
        }
        guard let state = try? JSONDecoder().decode(State.self, from: data) else {
            return .unreadable(corrupt: true)
        }
        unreadableSince.withLock { $0 = nil }
        return .state(state)
    }

    private static func save(_ state: State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount
        ]
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else {
            if status != errSecSuccess {
                AppLogger.security.error("PIN throttle state not saved (status: \(status, privacy: .public))")
            }
            return
        }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus != errSecSuccess {
            AppLogger.security.error("PIN throttle state not saved (status: \(addStatus, privacy: .public))")
        }
    }
}
