//
//  ModelPicker.swift
//  iPhoneUse
//
//  Searchable model list with a custom-ID field. Adapted from esp32-iphone-agent's
//  ModelPicker / ModelSelectionView (https://github.com/onehumanbeing/esp32-iphone-agent, MIT).
//

import SwiftUI

struct ModelPicker: View {
    @ObservedObject var settings: LLMSettings
    @ObservedObject private var language = LanguageStore.shared
    @State private var showingModels = false

    var body: some View {
        Button { showingModels = true } label: {
            LabeledContent {
                Text(settings.model.isEmpty ? t("选择模型") : settings.model)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            } label: {
                Text(t("模型"))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.haptic(.plain))
        .sheet(isPresented: $showingModels) {
            ModelSelectionView(settings: settings)
        }
    }
}

struct ModelSelectionView: View {
    @ObservedObject var settings: LLMSettings
    @ObservedObject private var language = LanguageStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var customID = ""

    private var matches: [String] {
        Set(settings.models + [settings.model]).filter {
            !$0.isEmpty
                && !LLMEndpoint.isTextOnly($0)
                && (search.isEmpty || $0.localizedStandardContains(search))
        }.sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(t("模型 ID"), text: $customID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(useCustomID)
                    Button(t("使用该模型 ID"), action: useCustomID)
                        .disabled(customID.trimmingCharacters(in: .whitespaces).isEmpty)
                        .glassButton(prominent: true)
                } header: {
                    Text(t("自定义模型"))
                } footer: {
                    Text(t("该模型需要支持图片输入和工具调用。"))
                }
                Section {
                    ForEach(matches, id: \.self) { id in
                        Button { choose(id) } label: {
                            HStack {
                                Text(id).foregroundStyle(.primary)
                                Spacer()
                                if id == settings.model {
                                    Image(systemName: "checkmark").accessibilityLabel(t("已选择"))
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.haptic(.plain))
                    }
                    if settings.loadingModels {
                        ProgressView { Text(t("正在加载模型…")) }
                    } else if let error = settings.modelsError {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(t("模型"))
                }
            }
            .searchable(text: $search, prompt: Text(t("搜索模型")))
            .navigationTitle(t("选择模型"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("取消")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await settings.loadModels() } } label: {
                        Label(t("刷新"), systemImage: "arrow.clockwise")
                    }
                    .disabled(settings.loadingModels)
                }
            }
            .task {
                if settings.models.isEmpty { await settings.loadModels() }
            }
        }
    }

    private func useCustomID() {
        let id = customID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { choose(id) }
    }

    private func choose(_ id: String) {
        settings.model = id
        dismiss()
    }
}
