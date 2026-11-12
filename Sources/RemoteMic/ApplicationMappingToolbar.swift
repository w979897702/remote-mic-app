import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ApplicationMappingToolbar: View {
    @ObservedObject var store: ApplicationButtonMappingStore
    @ObservedObject var localization: LocalizationStore
    @Binding var selection: UUID?
    @State private var failed = false
    @State private var confirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        scopeButton(localization.text("button_mapping.app.global"), id: nil)
                        Text("button_mapping.app.specific")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        ForEach(store.profiles) { profile in
                            scopeButton(profile.displayName, id: profile.id)
                        }
                    }
                    .padding(2)
                }
                Button("button_mapping.app.add", systemImage: "plus") { chooseApplication() }
                    .disabled(store.storageUnavailable)
                if selection != nil {
                    Button(role: .destructive) { confirmingRemoval = true } label: {
                        Image(systemName: "trash")
                    }
                    .help(localization.text("button_mapping.app.remove"))
                    .accessibilityLabel(localization.text("button_mapping.app.remove"))
                }
            }
            Text(selection == nil ? "button_mapping.app.global_hint" : "button_mapping.app.inherit_hint")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if failed || store.storageUnavailable {
                HStack {
                    Text("button_mapping.app.save_failed").foregroundStyle(.red)
                    Button("button_mapping.app.reload") { failed = !store.reload() }
                }.font(.system(size: 12))
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 8)
        .alert(localization.text("button_mapping.app.remove"), isPresented: $confirmingRemoval) {
            Button(localization.text("common.action.cancel"), role: .cancel) {}
            Button(localization.text("button_mapping.app.remove"), role: .destructive) {
                guard let selection else { return }
                failed = !store.remove(selection)
                if !failed { self.selection = nil }
            }
        } message: { Text("button_mapping.app.remove_hint") }
        .onChange(of: store.profiles.map(\.id)) { ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
    }

    private func scopeButton(_ title: String, id: UUID?) -> some View {
        Button { selection = id } label: {
            Text(title).font(.system(size: 13, weight: .medium))
                .lineLimit(1).padding(.horizontal, 10).padding(.vertical, 6)
                .background(selection == id ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.07), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == id ? .isSelected : [])
        .help(title)
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = localization.text("button_mapping.app.add")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        AppLogger.shared.write("APP MAPPING action=choose_application phase=requested result=requested")
        guard panel.runModal() == .OK, let url = panel.url else {
            AppLogger.shared.write("APP MAPPING action=choose_application phase=completed result=cancelled reason=user_cancelled")
            return
        }
        // 用户明确选择的 App 只取公开 Bundle 元数据，不访问其配置或沙盒。
        guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else {
            failed = true
            return
        }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        if let id = store.add(bundleIdentifier: identifier, displayName: name) {
            selection = id
            failed = false
        } else { failed = true }
    }
}
