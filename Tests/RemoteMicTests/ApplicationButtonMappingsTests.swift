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

    @Test func interactionOverridesInheritAndPreserveExplicitOff() throws {
        try withSettings { settings, defaults in
            settings.customMappingEnabled = true
            let device = settings.selectedRemoteProfileID
            settings.setHoldMode(.repeatSingle, for: .left)
            settings.setAllowsRapidPress(true, for: .home)
            let store = settings.applicationMappings
            let id = try #require(store.add(bundleIdentifier: "org.example.App", displayName: "App"))
            store.activate(bundleIdentifier: "org.example.App")
            #expect(settings.buttonInteractionSettings().mode(for: .left) == .repeatSingle)
            #expect(store.writeInteraction(profile: id, device: device, button: .left) { $0.hold = .once })
            #expect(store.writeInteraction(profile: id, device: device, button: .home) { $0.rapid = false })
            #expect(settings.buttonInteractionSettings().mode(for: .left) == .once)
            #expect(settings.allowsRapidPress(for: .home, profileID: device) == false)
            #expect(settings.interactionSettings.mode(for: .left) == .repeatSingle)
            #expect(settings.allowsRapidPress(for: .home))
            #expect(store.interaction(profile: id, device: UUID(), button: .left) == nil)
            let loaded = AppSettings(defaults: defaults)
            loaded.applicationMappings.activate(bundleIdentifier: "org.example.App")
            #expect(loaded.buttonInteractionSettings().mode(for: .left) == .once)
            settings.customMappingEnabled = false
            #expect(settings.buttonInteractionSettings().mode(for: .left) == .repeatSingle)
            settings.customMappingEnabled = true
            store.activate(bundleIdentifier: "org.example.Other")
            #expect(settings.buttonInteractionSettings().mode(for: .left) == .repeatSingle)
            store.activate(bundleIdentifier: "org.example.App")
            #expect(store.writeInteraction(profile: id, device: device, button: .left) { $0.hold = nil })
            #expect(settings.buttonInteractionSettings().mode(for: .left) == .repeatSingle)
            settings.setHoldMode(.once, for: .left)
            #expect(settings.buttonInteractionSettings().mode(for: .left) == .once)
        }
    }

    @Test func timingOverridesAndBackupPreserveGlobalAndLegacyData() throws {
        try withSettings { settings, _ in
            settings.customMappingEnabled = true
            let store = settings.applicationMappings
            let id = try #require(store.add(bundleIdentifier: "org.example.App", displayName: "App"))
            let model = XiaomiRemoteModel.rc003
            let device = settings.registerBluetoothRemote(identifier: UUID())
            settings.updateRemoteProfileModel(device, model: model)
            settings.selectRemoteProfile(device)
            let base = settings.buttonGestureTiming(for: model)
            let timing = RemoteButtonGestureTiming(doubleClickMilliseconds: 150, longPressMilliseconds: 850,
                repeatSingleStartMilliseconds: 250)
            #expect(store.writeTiming(timing, profile: id, model: model))
            store.activate(bundleIdentifier: "org.example.App")
            #expect(settings.effectiveButtonGestureTiming(for: model) == timing)
            #expect(settings.interactionSnapshot(for: .ok).settings.longPressMilliseconds == 850)
            #expect(settings.interactionSnapshot(for: .ok).settings.doubleClickMilliseconds == 150)
            #expect(settings.interactionSnapshot(for: .ok).repeatSingleStartMilliseconds == 250)
            #expect(settings.buttonInteractionSettings(useActiveApplication: false).timing == base)
            #expect(settings.buttonGestureTiming(for: model) == base)
            let backup = try settings.exportedConfigurationData()
            let object = try #require(JSONSerialization.jsonObject(with: backup) as? [String: Any])
            #expect(object["formatVersion"] as? Int == 4)
            let full = try MacConfigurationBackup(host: settings.completeConfigurationSnapshot(), components: nil)
                .encoded(version: "2.0.0", build: "9")
            let decoded = try MacConfigurationBackup.decode(full)
            try withSettings { destination, _ in
                try destination.applyPortableLocalSnapshot(destination.validatedCompleteConfigurationSnapshot(decoded.host))
                #expect(destination.applicationMappings.profiles == store.profiles)
            }
            #expect(store.writeTiming(nil, profile: id, model: model))
            #expect(settings.effectiveButtonGestureTiming(for: model) == base)
            try settings.importConfiguration(from: backup)
            #expect(store.timing(profile: id, model: model) == timing)
            let legacy = Data("[{\"id\":\"\(UUID().uuidString)\",\"bundleIdentifier\":\"org.example.Legacy\",\"displayName\":\"Legacy\",\"bindings\":[]}]".utf8)
            let profiles = try JSONDecoder().decode([ApplicationButtonMapping].self, from: legacy)
            #expect(profiles.first?.interactions == nil)
            #expect(profiles.first?.timings == nil)
        }
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
