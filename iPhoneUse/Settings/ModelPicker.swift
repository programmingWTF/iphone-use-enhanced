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
    @State private var showingModels = false

    var body: some View {
        Button { showingModels = true } label: {
            LabeledContent("模型") {
                Text(settings.model.isEmpty ? "选择模型" : settings.model)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
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
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var customID = ""

    private var matches: [String] {
        Set(settings.models + [settings.model]).filter {
            !$0.isEmpty && (search.isEmpty || $0.localizedStandardContains(search))
        }.sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("模型 ID", text: $customID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(useCustomID)
                    Button("使用该模型 ID", action: useCustomID)
                        .disabled(customID.trimmingCharacters(in: .whitespaces).isEmpty)
                        .glassButton(prominent: true)
                } header: {
                    Text("自定义模型")
                } footer: {
                    Text("该模型需要支持图片输入和工具调用。")
                }
                Section("模型") {
                    ForEach(matches, id: \.self) { id in
                        Button { choose(id) } label: {
                            HStack {
                                Text(id).foregroundStyle(.primary)
                                Spacer()
                                if id == settings.model {
                                    Image(systemName: "checkmark").accessibilityLabel("已选择")
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.haptic(.plain))
                    }
                    if settings.loadingModels {
                        ProgressView("正在加载模型…")
                    } else if let error = settings.modelsError {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $search, prompt: "搜索模型")
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("刷新", systemImage: "arrow.clockwise") { Task { await settings.loadModels() } }
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
