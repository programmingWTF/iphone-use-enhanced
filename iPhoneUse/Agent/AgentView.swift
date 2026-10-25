//
//  AgentView.swift
//  iPhoneUse
//
//  ChatGPT-style layout, after github.com/PallavAg/Apple-Intelligence-Chat:
//  bubbles for the user, plain text for the agent, a floating glass composer,
//  and past runs in a chat list that slides in from the left.
//

import SwiftUI
import UIKit

struct AgentView: View {
    @ObservedObject private var agent = PhoneAgent.shared
    @ObservedObject private var connection = Connection.shared
    @ObservedObject private var llm = LLMSettings.shared
    @ObservedObject private var voice = VoiceRecorder.shared
    @State private var prompt = ""
    @FocusState private var composerFocused: Bool
    @State private var openRun: RunRecord.ID? // nil = the live chat
    @State private var menuOpen = false
    @State private var drag: CGFloat = 0
    @State private var carousels = CarouselFrames()
    @State private var showSettings = false
    @State private var showShortcutsGuide = false

    var body: some View {
        GeometryReader { geo in
            let menuWidth = min(geo.size.width * 0.8, 340)
            let offset = min(max((menuOpen ? menuWidth : 0) + drag, 0), menuWidth)
            ZStack(alignment: .leading) {
                ChatList(agent: agent, width: menuWidth, openRun: openRun, select: select,
                         reuse: { prompt = $0; select(nil) }, needsSetup: needsSetup, openSettings: { showSettings = true },
                         openShortcutsGuide: { showShortcutsGuide = true })
                    .accessibilityHidden(!menuOpen)
                // The mask reaches the screen edges, so the rounded corners follow the
                // display's instead of clipping the toolbar buttons.
                chat
                    .environment(\.carouselFrames, carousels)
                    .background(Color(.systemBackground))
                    .mask { RoundedRectangle(cornerRadius: offset > 0 ? 44 : 0, style: .continuous).ignoresSafeArea() }
                    .shadow(color: .black.opacity(offset > 0 ? 0.15 : 0), radius: 12)
                    .overlay {
                        if menuOpen { Color.black.opacity(0.001).onTapGesture { setMenu(false) } }
                    }
                    .offset(x: offset)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .global)
                    .onChanged { g in
                        // A swipe that starts on a step carousel scrolls it, not the drawer.
                        if !menuOpen, carousels.frames.values.contains(where: { $0.contains(g.startLocation) }) { return }
                        if abs(g.translation.width) > abs(g.translation.height) { drag = g.translation.width }
                    }
                    .onEnded { _ in
                        let open = drag > 80 || (menuOpen && drag > -80)
                        withAnimation(.snappy) { menuOpen = open; drag = 0 }
                        if open { composerFocused = false }
                    }
            )
            .sensoryFeedback(.impact(weight: .light), trigger: menuOpen)
            // Distinct from the chat's systemBackground so the panels separate in dark mode,
            // where the shadow is invisible.
            .background(Color(.secondarySystemBackground))
        }
        .onAppear { composerFocused = true } // keyboard up at launch, ready to type
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showShortcutsGuide) {
            NavigationStack {
                ShortcutsGuideView().toolbar { Button("完成") { showShortcutsGuide = false } }
            }
        }
        // iphoneuse://run?prompt=... starts a new session, like the Run Agent intent.
        .onOpenURL { url in
            if CellularShortcut.handle(url) { return }
            guard let linked = DeepLink.prompt(from: url), !agent.isRunning else { return }
            showSettings = false
            showShortcutsGuide = false
            openRun = nil
            setMenu(false)
            agent.run(prompt: linked)
        }
        .task {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "demoChat") { return agent.runDemo() }
            #endif
            await connection.connect()
            // Test hooks: `devicectl device process launch ... -agentScript "..."` (no LLM, see
            // scripts/runscript.sh) or `-agentPrompt "..."` (real run).
            let launchArgs = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            guard !agent.isRunning, agent.log.isEmpty else { return }
            if let script = launchArgs["agentScript"] as? String {
                agent.runScript(script)
            } else if let auto = launchArgs["agentPrompt"] as? String, !auto.isEmpty {
                agent.run(prompt: auto)
            }
        }
    }

    private var entries: [ChatEntry] {
        guard let openRun else { return agent.entries }
        guard let run = agent.history.first(where: { $0.id == openRun }) else { return [] }
        return run.entries ?? [ChatEntry(kind: .user, text: run.prompt), ChatEntry(kind: .assistant, text: run.log)]
    }

    /// Consecutive steps collapse into one carousel row.
    private var rows: [[ChatEntry]] {
        entries.reduce(into: []) { rows, entry in
            if entry.kind == .step, rows.last?.first?.kind == .step { rows[rows.count - 1].append(entry) } else { rows.append([entry]) }
        }
    }

    private var chat: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(rows, id: \.first!.id) { row in
                        if row[0].kind == .step { StepCarousel(steps: row) } else { ChatRow(entry: row[0]) }
                    }
                    if agent.isRunning && agent.question == nil && openRun == nil { PulsingDots() }
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            // 顶上那层「蒙版」是 iOS 26 自动加的 scroll edge effect：内容滚到栏下面时
            // 系统会盖一层模糊/渐变。聊天页要干净，直接关掉（设置页不经过这里）。
            .hidingTopScrollEdgeEffect()
            .overlay {
                if entries.isEmpty { suggestions }
            }
            // Floats over the chat: it changes size while connecting at launch, and as part of
            // the bottom inset it made the suggestions jump.
            .overlay(alignment: .top) {
                if !isConnected {
                    ConnectionStatus(connection: connection, openSettings: { showSettings = true })
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                        .glassPill()
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: connection.step)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    DDIProgressCard()
                        .animation(.snappy, value: DDIDownloadCenter.shared.isRunning)
                    if let error = voice.error {
                        Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal, 20)
                    }
                    if agent.isRunning {
                        Button { agent.stop() } label: {
                            Label("停止会话", systemImage: "stop.fill")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .glassButton(prominent: true, tint: .red)
                        .buttonBorderShape(.capsule)
                        .padding(.horizontal, 12)
                    }
                    composer
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // 聊天页不要导航栏那层半透明遮挡：内容直接滚到状态栏底下，顶上只留两个按钮。
            // 设置页是另一个推入的栈，仍然保留系统默认的栏背景。
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("会话列表", systemImage: "line.3.horizontal") { setMenu(true) }
                }
                // A round purple glass button, the same hue as the send button: Settings
                // moved to the drawer, so the top-right corner is a single circle. The
                // circle is drawn here instead of going through the toolbar's glass
                // button style, because that style shapes the item with the system's
                // capsule border and the result is a rounded square, not a circle.
                //
                // On iOS 26 the bar would also put this item in the shared Liquid Glass
                // capsule, which showed as a ring of plain glass around the circle — the
                // "plain glass under coloured glass" the owner kept seeing. Asking for no
                // shared background leaves the purple circle alone in the corner.
                ToolbarItem(placement: .topBarTrailing) {
                    Button { select(nil) } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .glassCircle(GlassTint.purple)
                    }
                    .buttonStyle(.haptic(.plain))
                    .disabled(newSessionDisabled)
                    .opacity(newSessionDisabled ? 0.55 : 1)
                    .accessibilityLabel("新会话")
                }
                .withoutSharedBackground()
            }
        }
    }

    private static let suggestions = [
        ("message.fill", Color.green, "看看微信里有没有等我回的消息，列出来，先别回"),
        ("bag.fill", Color.orange, "用美团外卖点一份附近评分高的午饭，别超过 30 元"),
        ("creditcard.fill", Color.blue, "打开支付宝，看看这个月的账单都花在哪了"),
    ]

    /// Starter prompts on a new chat, sitting just above the composer.
    /// No glass at all: only a hairline rim, so the three starters stay quiet on a page
    /// that already has the composer's glass above them.
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.suggestions, id: \.2) { icon, tint, text in
                Button {
                    prompt = text
                    send()
                } label: {
                    HStack(spacing: 12) {
                        // Fixed width: the symbols differ in width, the texts should still line up.
                        Image(systemName: icon).foregroundStyle(tint).frame(width: 24)
                        Text(text).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.haptic(.plain))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                }
            }
        }
        .padding(.horizontal, 20) // same inset as the status rows below
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 8)
    }

    /// Red dot on the gear: something in the Settings checklist stops the agent from running.
    private var needsSetup: Bool {
        if llm.problem != nil { return true }
        if case .failed = connection.step { return true }
        return false
    }

    /// Nothing to clear on a fresh, idle chat.
    private var newSessionDisabled: Bool {
        openRun == nil && (agent.entries.isEmpty || agent.isRunning)
    }

    private var isConnected: Bool {
        if case .ready = connection.step { true } else { false }
    }

    private func setMenu(_ open: Bool) {
        if open { composerFocused = false }
        withAnimation(.snappy) { menuOpen = open }
    }

    /// Shows a past run, or for nil the live chat (cleared when nothing is running).
    private func select(_ id: RunRecord.ID?) {
        if id == nil, openRun == nil, !agent.isRunning { agent.entries = [] }
        openRun = id == agent.liveRun?.id ? nil : id // the live run shows as the live chat
        setMenu(false)
    }

    /// While running, the composer only answers the agent's question.
    private var composerEnabled: Bool { !agent.isRunning || agent.question != nil }

    private var canSend: Bool {
        composerEnabled && (voice.state == .recording || voice.state == .idle && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if voice.state == .idle {
                TextField(agent.question == nil ? "问点什么" : "回答", text: $prompt, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .frame(minHeight: 34)
                    .padding(.leading, 6)
            } else {
                Waveform(levels: voice.levels, transcribing: voice.state == .transcribing)
            }
            if composerEnabled {
                MicButton(voice: voice, enabled: llm.voiceAvailable) { finishVoice(send: false) }
            }
            // 和右上角、抽屉里那两个按钮同一个紫色实底；箭头用白色才压得住饱和度。
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(canSend ? Color.white : Color.secondary)
                    .glassCircle(canSend ? GlassTint.purple : nil)
            }
            .disabled(!canSend)
            .accessibilityLabel(agent.question == nil ? "发送" : "发送回答")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .padding(.leading, 8)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture { composerFocused = true }
        // 半透明，但只把背后的东西糊掉，不做折射（不用 glassEffect）：这样既看得见
        // 下面的内容，多行文字也不会和背后的消息叠在一起读不清。
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .sensoryFeedback(.start, trigger: voice.state) { _, new in new == .recording }
        .sensoryFeedback(.stop, trigger: voice.state) { old, _ in old == .recording }
        .sensoryFeedback(.error, trigger: voice.error) { _, new in new != nil }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onChange(of: agent.question) { _, question in
            if question != nil { openRun = nil; setMenu(false); composerFocused = true }
        }
    }

    // Every run starts fresh for the model, so sending always opens the live chat.
    // Mid-run, sending answers the agent's question instead.
    private func send() {
        if voice.state == .recording { return finishVoice(send: true) }
        guard canSend else { return }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        openRun = nil
        if agent.isRunning { agent.answer(text) } else { agent.run(prompt: text) }
        prompt = ""
        composerFocused = false
    }

    private func finishVoice(send: Bool) {
        composerFocused = false
        Task {
            guard let text = await voice.finish(), !text.isEmpty else { return }
            prompt = prompt.isEmpty ? text : prompt + " " + text
            if send { self.send() }
        }
    }
}

/// Tap to start (it becomes a stop button), or hold and release.
private struct MicButton: View {
    @ObservedObject var voice: VoiceRecorder
    let enabled: Bool
    let stop: () -> Void
    @State private var pressStart: Date?
    @State private var startedByPress = false

    var body: some View {
        Image(systemName: voice.state == .recording ? "stop.fill" : "mic")
            .font(.system(size: voice.state == .recording ? 13 : 17, weight: .semibold))
            .foregroundStyle(enabled && voice.state != .transcribing ? Color.primary : .secondary)
            .frame(width: GlassMetrics.circle, height: GlassMetrics.circle)
            .background(Circle().fill(voice.state == .recording ? Color(.secondarySystemFill) : .clear))
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard enabled, pressStart == nil else { return }
                    pressStart = .now
                    startedByPress = voice.state == .idle
                    if startedByPress { Task { await voice.start() } }
                }
                .onEnded { _ in
                    guard let start = pressStart else { return }
                    pressStart = nil
                    let held = Date.now.timeIntervalSince(start) > 0.4
                    if voice.state == .recording, !startedByPress || held { stop() }
                })
            .accessibilityLabel(voice.state == .recording ? "停止录音" : "语音输入")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if voice.state == .recording { stop() } else if enabled { Task { await voice.start() } }
            }
    }
}

/// Live input levels in place of the text field while recording, newest on the right.
private struct Waveform: View {
    let levels: [Float]
    let transcribing: Bool

    var body: some View {
        // Bars sit in an overlay so a full row can't widen the composer.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .overlay(alignment: .trailing) {
                HStack(spacing: 2) {
                    ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                        Capsule().frame(width: 3, height: 3 + CGFloat(level) * 24)
                    }
                }
                .foregroundStyle(transcribing ? .tertiary : .primary)
            }
            .clipped()
            .overlay { if transcribing { ProgressView() } }
            .animation(.linear(duration: 0.08), value: levels)
    }
}

/// The drawer behind the chat: past runs, newest first, plus new chat and settings.
private struct ChatList: View {
    @ObservedObject var agent: PhoneAgent
    let width: CGFloat
    let openRun: RunRecord.ID?
    let select: (RunRecord.ID?) -> Void
    let reuse: (String) -> Void
    let needsSetup: Bool
    let openSettings: () -> Void
    let openShortcutsGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("历史记录")
                .font(.largeTitle.bold())
                .padding(.horizontal, 20)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(agent.history) { run in
                        Button { select(run.id) } label: {
                            historyRow(run)
                        }
                        .buttonStyle(.haptic(.plain))
                        .contextMenu {
                            Button("使用该提示词", systemImage: "arrow.uturn.left") { reuse(run.prompt) }
                            Button("删除", systemImage: "trash", role: .destructive) {
                                if openRun == run.id { select(nil) }
                                agent.deleteRun(run.id)
                            }
                        } preview: {
                            // 参考 ChatGPT：抬起的是整张宽卡片，正文完整，不是原来那一行。
                            historyPreview(run)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .overlay {
                if agent.history.isEmpty { Text("还没有会话").foregroundStyle(.secondary) }
            }
            // 底部这三个按钮改成给列表的 safeAreaInset：滚动区到此为止，最后一行会停在
            // 按钮上方，而不是被按钮压住一半。底色用抽屉自己的背景色，所以看不到「一条
            // 挡在文字上的带子」，只是列表到这里就结束。
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 12) {
                    Button(action: openShortcutsGuide) {
                        HStack {
                            Label("接入快捷指令与深链", systemImage: "link")
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.haptic(.plain))
                    .background(Color(.secondarySystemBackground), in: Capsule())
                    .overlay { Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1) }
                    // 与下面那排（「对话」+ 齿轮）同一个 20pt 内边距：三者的左右两端要齐平，
                    // 否则这一条会比下面两个按钮各宽 12pt，看着「长了一点点」。
                    .padding(.horizontal, 20)
                    HStack {
                        // 和右上角的新会话圆钮、输入框的发送键同一个紫色、同一层实底，
                        // 三个按钮看起来是同一个东西，而不是三种紫。
                        Button { select(nil) } label: {
                            Label("对话", systemImage: "square.and.pencil")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 22)
                                .frame(height: GlassMetrics.circle)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.haptic(.plain))
                        .glassPill(GlassTint.purple, interactive: true)
                        Spacer()
                        Button(action: openSettings) {
                            Image(systemName: "gearshape")
                                .font(.title3)
                                .foregroundStyle(.primary)
                                .glassCircle()
                                .overlay(alignment: .topTrailing) { if needsSetup { BadgeDot().padding(6) } }
                        }
                        .buttonStyle(.haptic(.plain))
                        .accessibilityLabel(needsSetup ? "设置，需先完成配置" : "设置")
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 10)
                .padding(.bottom, 2)
                .background(Color(.systemBackground))
            }
        }
        .padding(.vertical, 8)
        .frame(width: width, alignment: .leading)
    }

    /// 列表里的一行：单行、无边框。边框只属于抬起后的那张卡片，列表里任何一行都不画。
    private func historyRow(_ run: RunRecord) -> some View {
        Text(run.prompt)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                run.id == (openRun ?? agent.liveRun?.id) ? Color(.secondarySystemFill) : .clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .contentShape(Rectangle())
    }

    /// 长按抬起的那张卡片：接近抽屉宽度，正文完整换行、字号放大，紫色玻璃加一圈受光的
    /// 描边，让它是「一个立起来的物件」而不是浮在空中的文字。
    private func historyPreview(_ run: RunRecord) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(alignment: .leading, spacing: 12) {
            Text(run.prompt)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Text(run.date.formatted(date: .abbreviated, time: .shortened))
                if !run.model.isEmpty {
                    Text("·")
                    Text(run.model).lineLimit(1)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: max(width - 24, 0), alignment: .leading)
        .glassSurface(GlassTint.purpleSoft, in: shape)
        .glassOutline(GlassTint.purple, in: shape)
    }
}

private struct ChatRow: View {
    let entry: ChatEntry

    @State private var showingFullText = false
    @State private var copied = false

    var body: some View {
        switch entry.kind {
        case .user:
            // Purple, the same hue family as the send button: "from me" reads at a glance,
            // but at the softer weight — a paragraph of text does not need the button's
            // saturation.
            VStack(alignment: .trailing, spacing: 6) {
                Text(entry.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassSurface(GlassTint.purpleSoft, cornerRadius: 20)
                    .contextMenu {
                        Button { copyText() } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        Button { showingFullText = true } label: {
                            Label("选择文本", systemImage: "text.cursor")
                        }
                    }
                if copied { copiedBadge }
            }
            .animation(.easeOut(duration: 0.2), value: copied)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 48)
            .sheet(isPresented: $showingFullText) {
                MessageTextSheet(text: entry.text, isMarkdown: false)
            }
        case .assistant:
            // Plain glass for the agent: the reply shouldn't compete for colour.
            VStack(alignment: .leading, spacing: 6) {
                MarkdownText(text: entry.text, selectable: false)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(cornerRadius: 20)
                    .contextMenu {
                        Button { copyText() } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        Button { showingFullText = true } label: {
                            Label("选择文本", systemImage: "text.cursor")
                        }
                    }
                if copied { copiedBadge }
            }
            .animation(.easeOut(duration: 0.2), value: copied)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 24)
            .sheet(isPresented: $showingFullText) {
                MessageTextSheet(text: entry.text, isMarkdown: true)
            }
        case .step:
            Text(entry.text)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    /// Confirm the copy without an alert: a small pill under the bubble, gone in two seconds.
    private var copiedBadge: some View {
        Text("已复制")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassPill()
            .transition(.opacity)
    }

    /// The raw text, not the rendered markdown, so a reply pastes as the model wrote it.
    private func copyText() {
        UIPasteboard.general.string = entry.text
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeOut(duration: 0.15)) { copied = false }
        }
    }
}

/// Where the step carousels are on screen, so the drawer swipe can leave them alone.
/// A class so scrolling (which moves them) doesn't re-render the whole chat. Carousels write
/// into it through the environment: a preference wouldn't make it out of the NavigationStack.
private final class CarouselFrames { var frames: [ChatEntry.ID: CGRect] = [:] }

private struct CarouselFramesEnvironmentKey: EnvironmentKey {
    static let defaultValue = CarouselFrames()
}

private extension EnvironmentValues {
    var carouselFrames: CarouselFrames {
        get { self[CarouselFramesEnvironmentKey.self] }
        set { self[CarouselFramesEnvironmentKey.self] = newValue }
    }
}

/// A run's steps side by side, newest on the right and kept in view.
private struct StepCarousel: View {
    let steps: [ChatEntry]
    @State private var viewing: ChatEntry.ID?
    @Environment(\.carouselFrames) private var carousels

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("步骤").font(.headline)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    // ponytail: non-lazy so cards keep their fade state; fine for maxSteps-sized runs.
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(steps) { step in StepCard(entry: step, open: { viewing = step.id }).id(step.id) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, -16) // bleed to the screen edges
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { carousels.frames[steps[0].id] = $0 }
                .onDisappear { carousels.frames[steps[0].id] = nil }
                .onAppear { proxy.scrollTo(steps.last?.id, anchor: .trailing) }
                .onChange(of: steps.count) {
                    withAnimation(.easeOut(duration: 0.4)) { proxy.scrollTo(steps.last?.id, anchor: .trailing) }
                }
            }
        }
        .padding(.vertical, 12)
        .fullScreenCover(isPresented: Binding(get: { viewing != nil }, set: { if !$0 { viewing = nil } })) {
            ShotViewer(shots: steps.filter { $0.shot == true }, selection: $viewing)
        }
    }
}

/// Full screen screenshots of a run, swiped left and right, dots on top for position.
private struct ShotViewer: View {
    let shots: [ChatEntry]
    @Binding var selection: ChatEntry.ID?
    @Environment(\.dismiss) private var dismiss
    @State private var pull: CGFloat = 0 // swipe down to close

    var body: some View {
        let index = shots.firstIndex { $0.id == selection } ?? 0
        VStack(spacing: 12) {
            ZStack {
                if shots.count <= 20 {
                    HStack(spacing: 6) {
                        ForEach(shots.indices, id: \.self) { i in
                            Circle()
                                .fill(.primary.opacity(i == index ? 1 : 0.25))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .animation(.snappy, value: index)
                } else {
                    Text("\(index + 1) / \(shots.count)").font(.footnote.monospacedDigit().bold())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassPill()
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .glassCircle()
                }
                .buttonStyle(.haptic(.plain))
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 20)

            TabView(selection: $selection) {
                ForEach(shots) { shot in
                    VStack(spacing: 14) {
                        if let image = UIImage(contentsOfFile: shot.shotURL.path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Color(.separator), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
                        }
                        Text(shot.text)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 8)
                    .tag(Optional(shot.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: pull)
            .scaleEffect(1 - min(pull, 300) / 1500)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { g in
                        if g.translation.height > abs(g.translation.width) { pull = g.translation.height }
                    }
                    .onEnded { g in
                        if pull > 120 || g.predictedEndTranslation.height > 400 && pull > 0 { dismiss() }
                        else { withAnimation(.snappy) { pull = 0 } }
                    }
            )
        }
        .presentationBackground(.ultraThinMaterial) // the chat shows through, blurred
    }
}

private struct StepCard: View {
    let entry: ChatEntry
    let open: () -> Void
    @State private var image: UIImage?
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.shot == true {
                Group {
                    if let image { Image(uiImage: image).resizable() } else { Color(.secondarySystemFill) }
                }
                .aspectRatio(9 / 19.5, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(.separator), lineWidth: 0.5))
                .onTapGesture { tapHaptic(); open() }
            }
            Text(entry.text)
                .font(.caption.monospaced())
                .lineLimit(3)
            if let thought = entry.thought {
                Text(thought).font(.caption).foregroundStyle(.secondary).lineLimit(4)
            }
        }
        .frame(width: 150, alignment: .leading)
        .padding(10)
        .glassSurface(nil, cornerRadius: 20)
        .textSelection(.enabled)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 12)
        .scaleEffect(shown ? 1 : 0.95)
        .onAppear { withAnimation(.easeOut(duration: 0.45)) { shown = true } }
        .task { if entry.shot == true { image = UIImage(contentsOfFile: entry.shotURL.path) } }
    }
}

private struct BadgeDot: View {
    var body: some View {
        Circle().fill(.red).frame(width: 9, height: 9).offset(x: 3, y: -3)
    }
}

/// Typing indicator shown while the agent works.
private struct PulsingDots: View {
    @State private var on = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundStyle(.secondary)
                    .scaleEffect(on ? 1 : 0.5)
                    .opacity(on ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2), value: on)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassPill()
        .onAppear { on = true }
    }
}

/// iOS refuses new connections to this iPhone over cellular data; see Connection.blockedByCellular.
private struct CellularHelpView: View {
    let connect: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("iOS 不允许通过蜂窝数据连接这台 iPhone。请接入 Wi-Fi，或在连接时先关闭蜂窝数据：连上之后可以再打开。")
                }
                Section("方式一") {
                    Text("在控制中心关闭蜂窝数据，然后：")
                    Button("连接") { connect() }
                }
                Section {
                    Link(destination: CellularShortcut.installURL) {
                        Label("安装蜂窝数据开关快捷指令", systemImage: "square.and.arrow.down")
                    }
                    Button("连接") { connect() }
                } header: {
                    Text("方式二")
                } footer: {
                    Text("这个快捷指令只需添加一次。之后连接时 App 会自行关闭再打开蜂窝数据。")
                }
            }
            .navigationTitle("使用蜂窝数据时")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("关闭") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ConnectionStatus: View {
    @ObservedObject var connection: Connection
    let openSettings: () -> Void
    @State private var showCellularHelp = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch connection.step {
            case .idle:
                Image(systemName: "circle").foregroundStyle(.secondary)
                Text("未连接").foregroundStyle(.secondary)
            case .working(let message):
                ProgressView().controlSize(.mini)
                if DDIDownloadCenter.shared.isRunning {
                    Text("\(message) \(Int((DDIDownloadCenter.shared.fraction * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                } else {
                    Text(message).foregroundStyle(.secondary)
                }
            case .ready:
                Image(systemName: "circle.fill").foregroundStyle(.green)
                Text("已连接这台 iPhone")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).foregroundStyle(.secondary)
            }
            Spacer()
            if showsConnect {
                // Without a pairing file, connecting fails instantly with the same message: send to Settings instead.
                if connection.hasPairingFile {
                    Button("连接") { connect() }
                        .glassButton()
                        .controlSize(.small)
                } else {
                    Button("去设置", action: openSettings)
                        .glassButton()
                        .controlSize(.small)
                }
            }
        }
        .font(.footnote)
        .sheet(isPresented: $showCellularHelp) {
            CellularHelpView {
                showCellularHelp = false
                connect()
            }
        }
    }

    /// Opens the cellular help sheet when the attempt fails on cellular data.
    private func connect() {
        Task {
            await connection.connect(force: true, userInitiated: true)
            showCellularHelp = connection.blockedByCellular
        }
    }

    private var showsConnect: Bool {
        switch connection.step {
        case .idle, .failed: true
        case .working, .ready: false
        }
    }
}

private extension View {
    /// Turns off the automatic scroll edge effect above a scroll view.
    ///
    /// iOS 26 fades and blurs scrolling content where it slides under a bar — that is the
    /// translucent band across the top of the chat. The chat wants its content to run all
    /// the way up, so the effect is switched off here; before iOS 26 there is nothing to
    /// switch off, and the modifier is skipped.
    @ViewBuilder
    func hidingTopScrollEdgeEffect() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}
