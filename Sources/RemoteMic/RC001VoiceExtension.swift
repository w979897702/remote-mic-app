import Foundation

/// 仅管理续期提交，不拥有收音、Fn 或停止行为；固件接受与否必须由真实音频验证。
final class RC001VoiceExtension {
    static let preferenceKey = "SayAllRC001VoiceExtendExperiment"
    private let schedule: VoiceFnTapSessionController.Scheduler
    private let log: (String) -> Void
    private var task: VoiceFnTapScheduledTask?
    private var generation: UInt64 = 0
    private var operationID: UInt64?
    private var submitted = 0

    init(
        schedule: @escaping VoiceFnTapSessionController.Scheduler = VoiceFnTapScheduledTask.mainQueue,
        log: @escaping (String) -> Void = { AppLogger.shared.write($0) }
    ) {
        self.schedule = schedule
        self.log = log
    }

    deinit { task?.cancel() }

    func start(
        enabled: Bool, model: XiaomiRemoteModel?, version: UInt16,
        sessionID: UInt8, operationID: UInt64,
        submit: @escaping (Data) -> Bool
    ) {
        stop(reason: "superseded")
        guard enabled else { return }
        guard model == .rc001, version >= 0x0100,
              (1...0x80).contains(sessionID) else {
            log("RC001 VOICE EXTEND operation_id=\(operationID) phase=skipped reason=ineligible_session model=\(model?.rawValue ?? "unknown")")
            return
        }
        self.operationID = operationID
        submitted = 0
        log("RC001 VOICE EXTEND operation_id=\(operationID) phase=started interval_ms=10000 session=\(sessionID)")
        scheduleNext(generation: generation, sessionID: sessionID, submit: submit)
    }

    func stop(reason: String) {
        generation &+= 1
        task?.cancel()
        task = nil
        guard let operationID else { return }
        self.operationID = nil
        log("RC001 VOICE EXTEND operation_id=\(operationID) phase=completed reason=\(reason) submitted_count=\(submitted) firmware_result=unknown")
    }

    private func scheduleNext(generation expected: UInt64, sessionID: UInt8,
                              submit: @escaping (Data) -> Bool) {
        task = schedule(10) { [weak self] in
            guard let self, generation == expected, let operationID else { return }
            // 已由 start 确认协议版本；使用精确 session，避免续期到别的会话。
            let written = submit(Data([0x0E, sessionID]))
            log("RC001 VOICE EXTEND operation_id=\(operationID) phase=write result=\(written ? "submitted" : "rejected") session=\(sessionID) remote_ack=unavailable")
            guard written else {
                stop(reason: "write_rejected")
                return
            }
            submitted += 1
            scheduleNext(generation: expected, sessionID: sessionID, submit: submit)
        }
    }
}
