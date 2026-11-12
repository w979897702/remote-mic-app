import Combine
import Foundation

/// 公开版的稀疏覆盖：缺少条目表示继承，显式 disabled 表示停用。
struct ApplicationButtonMapping: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var bundleIdentifier: String
    var displayName: String
    var bindings: [UnifiedButtonBinding] = []

    func binding(device: UUID?, button: RemoteButton, trigger: ButtonTrigger) -> ConfiguredButtonAction? {
        bindings.first { $0.remoteProfileID == device && $0.button == button && $0.trigger == trigger }?.configured
    }
}

final class ApplicationButtonMappingStore: ObservableObject {
    static let storageKey = "publicApplicationButtonMappingsV1"
    static var isSupported: Bool {
        #if canImport(SayAllButtonProfiles)
        false
        #else
        true
        #endif
    }

    @Published private(set) var profiles: [ApplicationButtonMapping] = []
    @Published private(set) var storageUnavailable = false
    @Published private(set) var activeBundleIdentifier: String?
    var onChange: (() -> Void)?
    private let defaults: UserDefaults
    private var operation = 0

    init(defaults: UserDefaults) {
        self.defaults = defaults
        _ = reload()
    }

    static func validate(_ profiles: [ApplicationButtonMapping]) throws {
        guard profiles.count <= 256,
              Set(profiles.map(\.id)).count == profiles.count,
              Set(profiles.map(\.bundleIdentifier)).count == profiles.count else {
            throw AppConfigurationError.invalidValues
        }
        for profile in profiles {
            guard !profile.bundleIdentifier.isEmpty, profile.bundleIdentifier.count <= 256,
                  profile.bundleIdentifier.range(of: "^[A-Za-z0-9][A-Za-z0-9.-]*$", options: .regularExpression) != nil,
                  !profile.displayName.isEmpty, profile.displayName.count <= 256,
                  profile.bindings.count <= 16384 else { throw AppConfigurationError.invalidValues }
            var keys = Set<String>()
            for binding in profile.bindings {
                let key = "\(binding.remoteProfileID?.uuidString ?? "global")/\(binding.button.rawValue)/\(binding.trigger.rawValue)"
                guard keys.insert(key).inserted,
                      binding.configured.normalizedForExecution == binding.configured,
                      AppSettings.validatedConfiguredAction(binding.configured) == binding.configured else {
                    throw AppConfigurationError.invalidValues
                }
            }
        }
    }

    @discardableResult func reload() -> Bool {
        do {
            let value = try defaults.data(forKey: Self.storageKey).map {
                try JSONDecoder().decode([ApplicationButtonMapping].self, from: $0)
            } ?? []
            try Self.validate(value)
            profiles = value
            storageUnavailable = false
            onChange?()
            return true
        } catch {
            storageUnavailable = true
            onChange?()
            AppLogger.shared.write("APP MAPPING action=load phase=failed result=unavailable reason=invalid_storage")
            return false
        }
    }

    @discardableResult func replace(_ value: [ApplicationButtonMapping]) -> Bool {
        guard !storageUnavailable else { return false }
        operation += 1
        AppLogger.shared.write("APP MAPPING operation_id=\(operation) action=save phase=requested result=requested")
        do {
            try Self.validate(value)
            let data = try JSONEncoder().encode(value)
            defaults.set(data, forKey: Self.storageKey)
            guard defaults.data(forKey: Self.storageKey) == data else { throw AppConfigurationError.invalidValues }
            profiles = value
            onChange?()
            AppLogger.shared.write("APP MAPPING operation_id=\(operation) action=save phase=completed result=stored count=\(value.count)")
            return true
        } catch {
            _ = reload()
            AppLogger.shared.write("APP MAPPING operation_id=\(operation) action=save phase=failed result=failed reason=storage_or_validation_failed")
            return false
        }
    }

    func add(bundleIdentifier: String, displayName: String) -> UUID? {
        if let existing = profiles.first(where: { $0.bundleIdentifier == bundleIdentifier }) { return existing.id }
        let profile = ApplicationButtonMapping(bundleIdentifier: bundleIdentifier, displayName: displayName)
        return replace(profiles + [profile]) ? profile.id : nil
    }

    @discardableResult func remove(_ id: UUID) -> Bool { replace(profiles.filter { $0.id != id }) }

    func binding(profile: UUID, device: UUID?, button: RemoteButton, trigger: ButtonTrigger) -> ConfiguredButtonAction? {
        profiles.first { $0.id == profile }?.binding(device: device, button: button, trigger: trigger)
    }

    func write(_ value: ConfiguredButtonAction?, profile: UUID, device: UUID?, button: RemoteButton, trigger: ButtonTrigger) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == profile }) else { return false }
        AppLogger.shared.write("APP MAPPING operation_id=\(operation + 1) action=write button=\(button.rawValue) trigger=\(trigger.rawValue) phase=requested result=requested inherit=\(value == nil)")
        var updated = profiles
        updated[index].bindings.removeAll { $0.remoteProfileID == device && $0.button == button && $0.trigger == trigger }
        if let value {
            updated[index].bindings.append(.init(remoteProfileID: device, button: button, trigger: trigger, configured: value))
        }
        return replace(updated)
    }

    /// 未知前台不清空选择，避免系统过渡阶段抖动；不记录 App 身份。
    func activate(bundleIdentifier: String?) {
        guard Self.isSupported, let bundleIdentifier, !bundleIdentifier.isEmpty,
              activeBundleIdentifier != bundleIdentifier else { return }
        activeBundleIdentifier = bundleIdentifier
        guard !profiles.isEmpty else { return }
        operation += 1
        AppLogger.shared.write("APP MAPPING operation_id=\(operation) action=activate phase=completed result=resolved scope=\(profiles.contains { $0.bundleIdentifier == bundleIdentifier } ? "application" : "global")")
    }

    func activeBinding(device: UUID?, button: RemoteButton, trigger: ButtonTrigger) -> ConfiguredButtonAction? {
        guard Self.isSupported, !storageUnavailable else { return nil }
        return profiles.first { $0.bundleIdentifier == activeBundleIdentifier }?.binding(device: device, button: button, trigger: trigger)
    }
}
