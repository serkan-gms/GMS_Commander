//
//  SettingsView.swift
//  GMS_Commander
//
//  Ayarlar penceresi (⌘,). Tüm tercihler `SettingsStore` üzerinden kaydedilir.
//

import SwiftUI
import AppKit

/// Ayarlar penceresi.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject private var theme: ThemeManager
    @State private var keyboardConflict: String?
    /// Son algılanan girdi olayı (fare geri tuşu tanılaması).
    @AppStorage(InputDiagnostics.defaultsKey) private var lastInputEvent = ""

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label(L.t("settings.tab.general"), systemImage: "slider.horizontal.3") }

            behaviorTab
                .tabItem { Label(L.t("settings.tab.behavior"), systemImage: "arrow.left.arrow.right") }

            appearanceTab
                .tabItem { Label(L.t("settings.tab.appearance"), systemImage: "paintpalette") }

            aboutTab
                .tabItem { Label(L.t("settings.tab.about"), systemImage: "info.circle") }
        }
        .frame(width: 580, height: 620)
    }

    private var generalTab: some View {
        Form {
            Section(L.t("settings.section.display")) {
                Toggle(L.t("settings.showHiddenFiles"), isOn: $settings.showHiddenFiles)
                Toggle(L.t("settings.foldersFirst"), isOn: $settings.foldersFirst)
                Toggle(L.t("settings.showRelativePath"), isOn: $settings.showRelativePathInSearch)
            }

            Section(L.t("settings.section.transfer")) {
                Picker(L.t("settings.conflictPolicy"), selection: $settings.conflictPolicy) {
                    ForEach(ConflictPolicy.allCases) { policy in
                        Text(policy.localizedTitle).tag(policy)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var behaviorTab: some View {
        Form {
            Section(L.t("settings.section.refresh")) {
                Toggle(L.t("settings.refreshAutomatically"), isOn: $settings.refreshAutomatically)
                Toggle(L.t("settings.gitIntegration"), isOn: $settings.gitIntegrationEnabled)
            }

            Section(L.t("settings.section.mouse")) {
                Toggle(
                    L.t("settings.mouseBackButton"),
                    isOn: $settings.mouseBackButtonEnabled
                )
                Text(L.t("settings.mouseBackButton.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    L.t(
                        "settings.mouseBackButton.detected",
                        lastInputEvent.isEmpty ? "—" : lastInputEvent
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(L.t("settings.section.startup")) {
                pathRow(
                    title: L.t("settings.leftPanelPath"),
                    text: $settings.leftPanelPath
                )
                pathRow(
                    title: L.t("settings.rightPanelPath"),
                    text: $settings.rightPanelPath
                )
            }

            Section(L.t("settings.section.keyboard")) {
                Text(L.t("settings.keyboard.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(KeyboardShortcutManager.FunctionKeyAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        Picker("", selection: functionKeyBinding(for: action)) {
                            ForEach(KeyboardShortcutManager.FunctionKey.allCases) { key in
                                Text(key.label).tag(key)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 92)
                    }
                }
                if let keyboardConflict {
                    Label(keyboardConflict, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button(L.t("settings.keyboard.reset")) {
                        settings.resetFunctionKeyBindings()
                        keyboardConflict = nil
                    }
                }
            }

            Section(L.t("settings.section.additionalShortcuts")) {
                Text(L.t("settings.additionalShortcuts.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(KeyboardShortcutManager.AdditionalShortcutAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        Picker("", selection: additionalShortcutBinding(for: action)) {
                            ForEach(KeyboardShortcutManager.AdditionalShortcutKey.allCases) { key in
                                Text(key.label).tag(key)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }
                HStack {
                    Spacer()
                    Button(L.t("settings.keyboard.reset")) {
                        settings.resetAdditionalShortcutBindings()
                        keyboardConflict = nil
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// Bir işlev tuşu eylemi için doğrulamalı seçim bağlaması üretir.
    private func functionKeyBinding(
        for action: KeyboardShortcutManager.FunctionKeyAction
    ) -> Binding<KeyboardShortcutManager.FunctionKey> {
        Binding(
            get: { settings.keyBindings.key(for: action) },
            set: { newKey in
                if let conflict = settings.setFunctionKey(newKey, for: action) {
                    keyboardConflict = L.t(
                        "settings.keyboard.conflict",
                        newKey.label,
                        conflict.title
                    )
                } else {
                    keyboardConflict = nil
                }
            }
        )
    }

    /// Değiştirilebilir macOS kısayolu için çakışma denetimli bağlama.
    private func additionalShortcutBinding(
        for action: KeyboardShortcutManager.AdditionalShortcutAction
    ) -> Binding<KeyboardShortcutManager.AdditionalShortcutKey> {
        Binding(
            get: { settings.additionalKeyBindings.key(for: action) },
            set: { newKey in
                if let conflict = settings.setAdditionalShortcut(newKey, for: action) {
                    keyboardConflict = L.t(
                        "settings.keyboard.conflict",
                        newKey.label,
                        conflict.title
                    )
                } else {
                    keyboardConflict = nil
                }
            }
        )
    }

    private var aboutTab: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(AppInfo.name)
                .font(.title3.weight(.semibold))
            Text(L.t("settings.version", AppInfo.version, AppInfo.build))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(L.t("settings.about.author", AppInfo.author))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(L.t("settings.about.description"))
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appearanceTab: some View {
        Form {
            Section(L.t("theme.title")) {
                Picker(L.t("theme.current"), selection: $theme.themeID) {
                    ForEach(ThemeID.allCases) { themeID in
                        Text(themeID.localizedName).tag(themeID)
                    }
                }
                .pickerStyle(.menu)

                Text(theme.themeID.localizedSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(L.t("settings.functionKeyFontSize"))
                    Slider(value: $theme.functionKeyFontSize, in: 9...20, step: 1)
                    Text("\(Int(theme.functionKeyFontSize))")
                        .monospacedDigit()
                        .frame(width: 24, alignment: .trailing)
                }

                HStack {
                    Text(L.t("settings.functionKeyButtonSize"))
                    Slider(value: $theme.functionKeyButtonScale, in: 0.8...1.5, step: 0.1)
                    Text("\(Int(theme.functionKeyButtonScale * 100))%")
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }

            Section(L.t("settings.section.interface")) {
                Toggle(L.t("settings.showFavoritesSidebar"), isOn: $settings.showFavoritesSidebar)
                Toggle(L.t("settings.showFunctionKeyBar"), isOn: $settings.showFunctionKeyBar)
                Toggle(L.t("settings.showStatusBar"), isOn: $settings.showStatusBar)
                Toggle(L.t("settings.showFileInfo"), isOn: $settings.showFileInfo)
                Toggle(L.t("settings.showPreviewPane"), isOn: $settings.showPreviewPane)
                Toggle(L.t("settings.singlePanelMode"), isOn: $settings.singlePanelMode)
                Toggle(L.t("settings.verticalSplit"), isOn: $settings.verticalSplit)
                Toggle(L.t("settings.restoreTabs"), isOn: $settings.restoreTabsOnLaunch)
                Picker(L.t("theme.fontStyle"), selection: $theme.fontStyle) {
                    ForEach(InterfaceFontStyle.allCases) { style in
                        Text(style.localizedName).tag(style)
                    }
                }
                .pickerStyle(.menu)
                HStack {
                    Text(L.t("theme.fontSize"))
                    Slider(value: $theme.fontSize, in: ThemeManager.fontSizeRange, step: 1)
                    Text("\(Int(theme.fontSize))")
                        .monospacedDigit()
                        .frame(width: 24, alignment: .trailing)
                }
                Text(L.t("theme.fontSize.sample"))
                    .font(Theme.mono(size: theme.fontSize))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.vertical, 4)
            }

            HStack {
                Spacer()
                Button(L.t("theme.reset")) {
                    theme.themeID = .voidCommander
                    theme.resetFontSize()
                    theme.resetFontStyle()
                    theme.functionKeyFontSize = 13
                    theme.functionKeyButtonScale = 1
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .environmentObject(theme)
    }

    private func pathRow(title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            Button(L.t("settings.choose")) {
                chooseDirectory { url in
                    text.wrappedValue = url.path
                }
            }
        }
    }

    private func chooseDirectory(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L.t("settings.choose")
        panel.message = L.t("settings.chooseMessage")
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }
}
