//
//  BatchRenameSheet.swift
//  GMS_Commander
//
//  Toplu yeniden adlandırma penceresi. Kurallar değiştikçe önizleme anında
//  yenilenir; çakışan veya geçersiz adlar kırmızı gösterilir ve uygulama
//  düğmesi kapatılır.
//

import SwiftUI

/// Toplu yeniden adlandırma penceresi.
struct BatchRenameSheet: View {
    let files: [URL]
    let onApplied: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var options = BatchRenameOptions()
    @State private var isApplying = false
    @State private var errorMessage: String?

    private var plan: BatchRenamePlan {
        BatchRenameService.plan(files: files, options: options)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollView {
                rules
                    .padding(12)
            }
            .frame(maxHeight: 260)
            Rectangle().fill(Theme.border).frame(height: 1)
            preview
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .frame(width: 820, height: 620)
        .background(Theme.panel)
    }

    private var header: some View {
        HStack {
            Image(systemName: "character.cursor.ibeam")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("batch.title"))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(L.t("batch.subtitle", files.count))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.header)
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text(L.t("batch.find")).gridColumnAlignment(.trailing)
                    TextField("", text: $options.find)
                        .textFieldStyle(.roundedBorder)
                    Text(L.t("batch.replace")).gridColumnAlignment(.trailing)
                    TextField("", text: $options.replace)
                        .textFieldStyle(.roundedBorder)
                    Toggle(L.t("batch.regex"), isOn: $options.useRegex)
                }
                GridRow {
                    Text(L.t("batch.prefix")).gridColumnAlignment(.trailing)
                    TextField("", text: $options.prefix)
                        .textFieldStyle(.roundedBorder)
                    Text(L.t("batch.suffix")).gridColumnAlignment(.trailing)
                    TextField("", text: $options.suffix)
                        .textFieldStyle(.roundedBorder)
                    Text("")
                }
                GridRow {
                    Text(L.t("batch.extension")).gridColumnAlignment(.trailing)
                    TextField(L.t("batch.extensionPlaceholder"), text: $options.newExtension)
                        .textFieldStyle(.roundedBorder)
                    Text(L.t("batch.case")).gridColumnAlignment(.trailing)
                    Picker("", selection: $options.caseMode) {
                        ForEach(BatchRenameOptions.CaseMode.allCases) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Text("")
                }
            }

            HStack(spacing: 12) {
                Toggle(L.t("batch.numbering"), isOn: $options.numberingEnabled)
                if options.numberingEnabled {
                    Text(L.t("batch.start"))
                    TextField("", value: $options.numberingStart, format: .number)
                        .frame(width: 56)
                        .textFieldStyle(.roundedBorder)
                    Text(L.t("batch.step"))
                    TextField("", value: $options.numberingStep, format: .number)
                        .frame(width: 56)
                        .textFieldStyle(.roundedBorder)
                    Text(L.t("batch.padding"))
                    TextField("", value: $options.numberingPadding, format: .number)
                        .frame(width: 48)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $options.numberAtStart) {
                        Text(L.t("batch.position.start")).tag(true)
                        Text(L.t("batch.position.end")).tag(false)
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
                Spacer()
                Button(L.t("batch.reset")) {
                    options = BatchRenameOptions()
                }
                .controlSize(.small)
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L.t("batch.preview"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(L.t("batch.changeCount", plan.changeCount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Table(plan.items) {
                TableColumn(L.t("batch.column.old")) { item in
                    Text(item.oldName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                TableColumn(L.t("batch.column.new")) { item in
                    Text(item.newName)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(item.error == nil ? Theme.textPrimary : Color.red)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                TableColumn(L.t("batch.column.status")) { item in
                    if let error = item.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    } else if item.isUnchanged {
                        Text(L.t("batch.status.unchanged"))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Label(L.t("batch.status.ready"), systemImage: "checkmark")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .width(min: 120, ideal: 170, max: 260)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
        .frame(minHeight: 180)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if plan.hasErrors {
                Label(L.t("batch.errorHint"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if isApplying {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button(L.t("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L.t("batch.apply")) { apply() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!plan.canApply || isApplying)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(Theme.header)
    }

    private func apply() {
        guard plan.canApply, !isApplying else { return }
        isApplying = true
        errorMessage = nil
        let currentPlan = plan

        Task {
            do {
                let count = try await Task.detached(priority: .userInitiated) {
                    try BatchRenameService.apply(currentPlan)
                }.value
                isApplying = false
                onApplied(count)
                dismiss()
            } catch {
                isApplying = false
                errorMessage = ErrorMessages.message(for: error)
            }
        }
    }
}
