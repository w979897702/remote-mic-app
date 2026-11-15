import Foundation
import Testing
@testable import RemoteMic

@Suite("RC001 语音续期候选")
struct RC001VoiceExtensionTests {
    @Test func physicalSessionContinuesBeyondTwoMinutesAndStopsOnRelease() {
        let scheduler = VoiceInputManualScheduler()
        var writes: [Data] = []
        var logs: [String] = []
        let lease = RC001VoiceExtension(schedule: scheduler.schedule, log: { logs.append($0) })
        lease.start(enabled: true, model: .rc001, version: 0x0100,
                    sessionID: 8, operationID: 108) { writes.append($0); return true }
        scheduler.advance(by: 9.99)
        #expect(writes.isEmpty)
        scheduler.advance(by: 115.01)
        #expect(writes == Array(repeating: Data([0x0E, 0xFF]), count: 12))
        lease.stop(reason: "remote_stop")
        scheduler.advance(by: 20)
        #expect(writes.count == 12)
        #expect(scheduler.pendingTaskCount == 0)
        #expect(logs.last?.contains("submitted_count=12") == true)
        #expect(logs.contains { $0.contains("session=8 target_session=255 remote_ack=unavailable") })
    }

    @Test func disabledOtherModelsLegacyAndHostSessionsNeverWrite() {
        let scheduler = VoiceInputManualScheduler()
        let lease = RC001VoiceExtension(schedule: scheduler.schedule, log: { _ in })
        var writes = 0
        let cases: [(Bool, XiaomiRemoteModel?, UInt16, UInt8)] = [
            (false, .rc001, 0x0100, 8), (true, .rc003, 0x0100, 8),
            (true, nil, 0x0100, 8), (true, .rc001, 0x0004, 8),
            (true, .rc001, 0x0100, 0), (true, .rc001, 0x0100, 0xFF)
        ]
        for (enabled, model, version, session) in cases {
            lease.start(enabled: enabled, model: model, version: version,
                        sessionID: session, operationID: 1) { _ in writes += 1; return true }
            scheduler.advance(by: 130)
        }
        #expect(writes == 0)
        #expect(scheduler.pendingTaskCount == 0)
    }

    @Test func rejectedWriteCancelsOnlyRenewalAndAllowsNextSession() {
        let scheduler = VoiceInputManualScheduler()
        var writes: [Data] = []
        var logs: [String] = []
        let lease = RC001VoiceExtension(schedule: scheduler.schedule, log: { logs.append($0) })
        lease.start(enabled: true, model: .rc001, version: 0x0100,
                    sessionID: 1, operationID: 1) { writes.append($0); return false }
        scheduler.advance(by: 120)
        #expect(writes.count == 1)
        #expect(logs.last?.contains("reason=write_rejected") == true)
        lease.start(enabled: true, model: .rc001, version: 0x0100,
                    sessionID: 2, operationID: 2) { writes.append($0); return true }
        scheduler.advance(by: 10)
        #expect(writes.last == Data([0x0E, 0xFF]))
        lease.stop(reason: "session_reset")
        scheduler.advance(by: 20)
        #expect(writes.count == 2)
        lease.start(enabled: false, model: .rc001, version: 0x0100,
                    sessionID: 3, operationID: 3) { writes.append($0); return true }
        scheduler.advance(by: 20)
        #expect(writes.count == 2)
    }

    @Test func lateCancelledTimerCannotRenewAnotherSession() {
        var callbacks: [() -> Void] = []
        var writes: [Data] = []
        let lease = RC001VoiceExtension(schedule: { _, callback in
            callbacks.append(callback)
            return VoiceFnTapScheduledTask {}
        }, log: { _ in })
        for session: UInt8 in [1, 2] {
            lease.start(enabled: true, model: .rc001, version: 0x0100,
                        sessionID: session, operationID: UInt64(session)) {
                writes.append($0); return true
            }
        }
        callbacks[0]()
        #expect(writes.isEmpty)
        callbacks[1]()
        #expect(writes == [Data([0x0E, 0xFF])])
        lease.stop(reason: "host_close")
        callbacks[2]()
        #expect(writes.count == 1)
    }
}
