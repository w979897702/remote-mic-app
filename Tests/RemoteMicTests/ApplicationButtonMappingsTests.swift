import Foundation
import Testing
@testable import RemoteMic

@Suite("公开版 App 专属映射")
struct ApplicationButtonMappingsTests {
    private func withSettings(_ run: (AppSettings, UserDefaults) throws -> Void) throws {
        let name = "ApplicationButtonMappingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try run(AppSettings(defaults: defaults), defaults)
    }

    @Test func sparseOverridesFollowForegroundAndLiveGlobalChanges() throws {
        try withSettings { settings, _ in
            settings.customMappingEnabled = true
            let device = settings.selectedRemoteProfileID
            settings.setBaseBinding(.init(action: .escape, shortcut: nil), for: .home, trigger: .singleClick, profileID: device)
            let store = settings.applicationMappings
            let first = try #require(store.add(bundleIdentifier: "org.example.First", displayName: "First"))
            let second = try #require(store.add(bundleIdentifier: "org.example.Second", displayName: "Second"))
            #expect(store.write(.init(action: .commandCopy, shortcut: nil), profile: first, device: device, button: .home, trigger: .singleClick))
            #expect(store.write(.disabled, profile: second, device: device, button: .home, trigger: .singleClick))
            store.activate(bundleIdentifier: "org.example.First")
            #expect(settings.action(for: .home) == .commandCopy)
            store.activate(bundleIdentifier: nil)
            #expect(settings.action(for: .home) == .commandCopy)
            store.activate(bundleIdentifier: "org.example.Second")
            #expect(settings.action(for: .home) == .disabled)
            store.activate(bundleIdentifier: "org.example.Other")
            #expect(settings.action(for: .home) == .escape)
            store.activate(bundleIdentifier: "org.example.First")
            settings.customMappingEnabled = false
            #expect(settings.action(for: .home) == .escape)
            settings.customMappingEnabled = true
            #expect(store.write(nil, profile: first, device: device, button: .home, trigger: .singleClick))
            settings.setBaseBinding(.init(action: .commandPaste, shortcut: nil), for: .home, trigger: .singleClick, profileID: device)
            #expect(settings.action(for: .home) == .commandPaste)
            #expect(store.remove(first))
            #expect(settings.action(for: .home) == .commandPaste)
        }
    }

    @Test func gesturesAndDevicesAreIndependentAndSurviveReload() throws {
        try withSettings { settings, defaults in
            settings.customMappingEnabled = true
            let device = settings.selectedRemoteProfileID
            let store = settings.applicationMappings
            let id = try #require(store.add(bundleIdentifier: "org.example.Editor", displayName: "Editor"))
            #expect(store.add(bundleIdentifier: "org.example.Editor", displayName: "Other name") == id)
            let globalBefore = try settings.exportedConfigurationData()
            let shortcut = ConfiguredButtonAction(action: .commandCopy, shortcut: nil)
            #expect(store.write(shortcut, profile: id, device: device, button: .ok, trigger: .doubleClick))
            store.activate(bundleIdentifier: "org.example.Editor")
            #expect(settings.configuredAction(for: .ok, trigger: .doubleClick) == shortcut)
            #expect(settings.configuredAction(for: .ok, trigger: .singleClick) == settings.configuredBaseAction(for: .ok, trigger: .singleClick))
            #expect(store.activeBinding(device: UUID(), button: .ok, trigger: .doubleClick) == nil)
            let reloaded = AppSettings(defaults: defaults)
            reloaded.applicationMappings.activate(bundleIdentifier: "org.example.Editor")
            #expect(reloaded.configuredAction(for: .ok, trigger: .doubleClick) == shortcut)
            var before = try #require(JSONSerialization.jsonObject(with: globalBefore) as? [String: Any])
            var after = try #require(JSONSerialization.jsonObject(with: settings.exportedConfigurationData()) as? [String: Any])
            before.removeValue(forKey: "applicationButtonMappings")
            before.removeValue(forKey: "formatVersion")
            after.removeValue(forKey: "applicationButtonMappings")
            after.removeValue(forKey: "formatVersion")
            #expect(NSDictionary(dictionary: before).isEqual(to: after))
        }
    }

    @Test func corruptStorageIsPreservedAndCanRecoverAfterRepair() throws {
        try withSettings { _, defaults in
            let bad = Data("invalid".utf8)
            defaults.set(bad, forKey: ApplicationButtonMappingStore.storageKey)
            let store = ApplicationButtonMappingStore(defaults: defaults)
            #expect(store.storageUnavailable)
            #expect(store.add(bundleIdentifier: "org.example.App", displayName: "App") == nil)
            #expect(defaults.data(forKey: ApplicationButtonMappingStore.storageKey) == bad)
            defaults.set(Data("[]".utf8), forKey: ApplicationButtonMappingStore.storageKey)
            #expect(store.reload())
            #expect(store.add(bundleIdentifier: "org.example.App", displayName: "App") != nil)
        }
    }

    @Test func backupRoundTripIncludesOverridesAndOldBackupStillLoads() throws {
        try withSettings { settings, _ in
            let device = settings.selectedRemoteProfileID
            let store = settings.applicationMappings
            let id = try #require(store.add(bundleIdentifier: "org.example.App", displayName: "App"))
            #expect(store.write(.disabled, profile: id, device: device, button: .home, trigger: .longPress))
            let backup = try settings.exportedConfigurationData()
            let complete = try MacConfigurationBackup(host: settings.completeConfigurationSnapshot(), components: nil)
                .encoded(version: "2.0.0", build: "7")
            let envelope = try #require(JSONSerialization.jsonObject(with: complete) as? [String: Any])
            #expect(envelope["schemaVersion"] as? Int == 3)
            let decoded = try MacConfigurationBackup.decode(complete)
            try withSettings { destination, _ in
                let validated = try destination.validatedCompleteConfigurationSnapshot(decoded.host)
                try destination.applyPortableLocalSnapshot(validated)
                #expect(destination.applicationMappings.profiles == store.profiles)
            }
            #expect(store.remove(id))
            try settings.importConfiguration(from: backup)
            #expect(store.binding(profile: id, device: device, button: .home, trigger: .longPress) == .disabled)
            var legacy = try #require(JSONSerialization.jsonObject(with: backup) as? [String: Any])
            legacy.removeValue(forKey: "applicationButtonMappings")
            legacy["formatVersion"] = 2
            try settings.importConfiguration(from: JSONSerialization.data(withJSONObject: legacy))
            #expect(store.profiles.isEmpty)
        }
    }

    @Test func invalidAndDuplicateEntriesDoNotReplaceSavedMappings() throws {
        try withSettings { settings, _ in
            let store = settings.applicationMappings
            let id = try #require(store.add(bundleIdentifier: "org.example.App", displayName: "App"))
            let saved = store.profiles
            #expect(!store.replace(saved + saved))
            #expect(store.profiles == saved)
            let savedIncompleteShortcut = store.write(.init(action: .customShortcut, shortcut: nil), profile: id,
                device: nil, button: .home, trigger: .singleClick)
            #expect(savedIncompleteShortcut == false)
            #expect(store.profiles == saved)
        }
    }
}
