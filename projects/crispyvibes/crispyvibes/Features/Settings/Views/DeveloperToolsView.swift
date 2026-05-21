import SwiftUI

struct DeveloperToolsView: View {
    let metricsStore: OperationMetricsStore
    let diagnosticsSnapshot: TerminalDiagnosticsSnapshot
    let acpObservabilityStore: ACPObservabilityStore
    @ObservedObject var experimentalFeatures: ExperimentalFeaturesService
    @ObservedObject var acpVibeSpaceContextStore: ACPVibeSpaceContextStore
    @ObservedObject var acpDeveloperToolsService: ACPDeveloperToolsService

    @State private var selectedTab = 0
    @State private var records: [OperationRecord] = []
    @State private var byOperation: [OperationAggregate] = []
    @State private var byProject: [OperationAggregate] = []
    @State private var terminalPayload: TerminalDiagnosticsPayload?
    @State private var acpPayload: ACPObservabilityPayload?
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Operations").tag(0)
                Text("Summary").tag(1)
                Text("Terminal").tag(2)
                Text("ACP").tag(3)
                Text("Remote").tag(4)
                Text("Auth").tag(5)
                Text("External").tag(6)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch selectedTab {
            case 0: operationsFeed
            case 1: aggregateSummary
            case 2: terminalDiagnostics
            case 3: acpDiagnostics
            case 4: remoteDiagnostics
            case 5: authDiagnostics
            case 6: externalSessionDiagnostics
            default: operationsFeed
            }
        }
        .onAppear {
            refresh()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                Task { @MainActor in refresh() }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        .accessibilityIdentifier("developerTools.view")
    }

    private func refresh() {
        records = metricsStore.snapshot()
        byOperation = metricsStore.aggregateByOperation().values.sorted { $0.totalDuration > $1.totalDuration }
        byProject = metricsStore.aggregateByProject().values.sorted { $0.totalDuration > $1.totalDuration }
        terminalPayload = diagnosticsSnapshot.capture()
        acpPayload = acpObservabilityStore.exportPayload(mode: experimentalFeatures.acpObservabilityMode)
        remoteEvents = AppDiagnostics.eventStore.snapshot().filter { $0.category == "remote" }
        authEvents = AppDiagnostics.eventStore.snapshot().filter { $0.category == "auth" }
        externalSessionEvents = AppDiagnostics.eventStore.snapshot().filter { $0.category == "external.sessions" }
    }

    // MARK: - Operations Feed (REQ-008)

    private var operationsFeed: some View {
        let parentIDs = Set(records.compactMap(\.parentID))
        let roots = records.filter { $0.parentID == nil }.sorted { $0.startTime > $1.startTime }
        let childrenByParent = Dictionary(grouping: records.filter { $0.parentID != nil }) { $0.parentID! }

        return List {
            ForEach(roots, id: \.id) { root in
                let isParent = parentIDs.contains(root.id)
                operationRow(root, indent: false, isParent: isParent)
                if let children = childrenByParent[root.id]?.sorted(by: { $0.startTime < $1.startTime }) {
                    ForEach(children, id: \.id) { child in
                        operationRow(child, indent: true, isParent: false)
                    }
                }
            }
        }
    }

    private func operationRow(_ record: OperationRecord, indent: Bool, isParent: Bool) -> some View {
        HStack {
            if indent {
                Rectangle().fill(.clear).frame(width: 20)
                Image(systemName: "arrow.turn.down.right")
                    .font(AppTypographyTokens.caption2)
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isParent {
                        Image(systemName: "folder").font(AppTypographyTokens.caption).foregroundStyle(.secondary)
                    }
                    Text(record.operationName)
                        .fontWeight(isParent ? .semibold : .medium)
                }
                HStack(spacing: 6) {
                    if let pane = record.paneKind {
                        Text(pane)
                            .font(AppTypographyTokens.caption)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if let ctx = record.projectContext {
                        Text(URL(fileURLWithPath: ctx).lastPathComponent)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let errorDescription = record.errorDescription, !errorDescription.isEmpty {
                    Text(errorDescription)
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            Text(formatDuration(record.duration))
                .monospacedDigit()
                .fontWeight(isParent ? .semibold : .regular)
            Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(record.succeeded ? .green : .red)
            VStack(alignment: .trailing, spacing: 0) {
                Text(record.startTime, style: .time)
                Text(record.endTime, style: .time)
            }
            .font(AppTypographyTokens.caption2)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Aggregate Summary (REQ-009)

    private var aggregateSummary: some View {
        List {
            Section("By Operation") {
                ForEach(byOperation, id: \.key) { agg in
                    aggregateRow(agg)
                }
            }
            Section("By Project") {
                ForEach(byProject, id: \.key) { agg in
                    aggregateRow(agg)
                }
            }
        }
    }

    private func aggregateRow(_ agg: OperationAggregate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(agg.key).fontWeight(.medium)
            HStack(spacing: 12) {
                label("count", "\(agg.count)")
                label("avg", formatDuration(agg.averageDuration))
                label("max", formatDuration(agg.maxDuration))
                if agg.failureCount > 0 {
                    label("failures", "\(agg.failureCount)")
                        .foregroundStyle(.red)
                }
            }
            .font(AppTypographyTokens.caption)
            .monospacedDigit()
        }
    }

    // MARK: - Terminal Diagnostics (REQ-011, 012)

    private var terminalDiagnostics: some View {
        let payload = terminalPayload ?? diagnosticsSnapshot.capture()
        return List {
            Section("Overview") {
                LabeledContent("Captured At", value: payload.capturedAt)
                LabeledContent("Active Sessions", value: "\(payload.activeSessionCount)")
                LabeledContent("Ghostty Surfaces", value: "\(payload.activeGhosttySurfaceCount)")
                LabeledContent("Active Hosts", value: "\(payload.activeHostCount)")
                LabeledContent("Polling Timers", value: "\(payload.activePollingTimerCount)")
                LabeledContent("Visible Tiles", value: "\(payload.visibleBoardTileCount)")
                LabeledContent("Spotlight Active", value: payload.spotlightActive ? "Yes" : "No")
            }
            Section("Sessions") {
                ForEach(payload.sessions, id: \.sessionDebugID) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(session.sessionDebugID)
                                .fontWeight(.medium)
                            Text(session.source)
                                .font(AppTypographyTokens.caption)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        HStack(spacing: 12) {
                            statusDot("visible", session.isVisible)
                            statusDot("focused", session.isFocused)
                            if let event = session.lastLifecycleEvent {
                                Text(event).font(AppTypographyTokens.caption).foregroundStyle(.secondary)
                            }
                        }
                        if session.shellLaunchDuration != nil
                            || session.renderLatency != nil
                            || session.interactiveLatency != nil
                        {
                            HStack(spacing: 12) {
                                if let v = session.shellLaunchDuration {
                                    label("shell", formatDuration(v))
                                }
                                if let v = session.renderLatency {
                                    label("render", formatDuration(v))
                                }
                                if let v = session.interactiveLatency {
                                    label("interactive", formatDuration(v))
                                }
                            }
                            .font(AppTypographyTokens.caption)
                            .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var acpDiagnostics: some View {
        let payload = acpPayload ?? acpObservabilityStore.exportPayload(mode: experimentalFeatures.acpObservabilityMode)

        return List {
            Section("Probe") {
                probeControls
            }

            if payload.mode == .disabled {
                Section("Status") {
                    developerToolsStatusRow(
                        title: "ACP observability is off",
                        detail: "Enable ACP observability in Settings > Experimental to capture structured ACP diagnostics while using ACP sessions."
                    )
                }
            } else if payload.eventCount == 0, payload.sessionCount == 0, payload.turnCount == 0 {
                Section("Status") {
                    developerToolsStatusRow(
                        title: "No ACP data yet",
                        detail: "Use the ACP probe above to connect to an installed agent and generate session activity."
                    )
                }
            } else {
                Section("Overview") {
                    LabeledContent("Mode", value: payload.mode.rawValue)
                    LabeledContent("Captured At", value: payload.capturedAt)
                    LabeledContent("Sessions", value: "\(payload.sessionCount)")
                    LabeledContent("Turns", value: "\(payload.turnCount)")
                    LabeledContent("Events", value: "\(payload.eventCount)")
                }

                Section("Sessions") {
                    ForEach(payload.sessions) { session in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(session.agentID).fontWeight(.medium)
                                Text(session.transportKind)
                                    .font(AppTypographyTokens.caption)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.quaternary)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                Text(session.connectionState)
                                    .font(AppTypographyTokens.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 12) {
                                label("origin", session.origin)
                                if let projectToken = session.projectToken {
                                    label("project", projectToken)
                                }
                                if let currentMode = session.currentMode {
                                    label("mode", currentMode)
                                }
                                if let currentModel = session.currentModel {
                                    label("model", currentModel)
                                }
                            }
                            .font(AppTypographyTokens.caption)
                            .monospacedDigit()
                            if let lastErrorClass = session.lastErrorClass {
                                Text(lastErrorClass)
                                    .font(AppTypographyTokens.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                Section("Turns") {
                    ForEach(payload.turns) { turn in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(turn.id).fontWeight(.medium)
                                if let agentID = turn.agentID {
                                    Text(agentID)
                                        .font(AppTypographyTokens.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            HStack(spacing: 12) {
                                label("assistant", "\(turn.counts.assistantChunkCount)")
                                label("thought", "\(turn.counts.thoughtChunkCount)")
                                label("tool", "\(turn.counts.toolCallCount)")
                                label("plan", "\(turn.counts.planUpdateCount)")
                                label("perm", "\(turn.counts.permissionRequestCount)")
                                label("term", "\(turn.counts.terminalRequestCount)")
                                label("file", "\(turn.counts.fileOperationCount)")
                            }
                            .font(AppTypographyTokens.caption)
                            .monospacedDigit()
                            if let stopReason = turn.stopReason {
                                Text(stopReason)
                                    .font(AppTypographyTokens.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Recent Events") {
                    ForEach(payload.events.reversed()) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(event.category).fontWeight(.medium)
                                if let method = event.method {
                                    Text(method)
                                        .font(AppTypographyTokens.caption)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.quaternary)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            HStack(spacing: 12) {
                                if let agentID = event.agentID {
                                    label("agent", agentID)
                                }
                                if let projectToken = event.projectToken {
                                    label("project", projectToken)
                                }
                                if let duration = event.duration {
                                    label("duration", formatDuration(duration))
                                }
                                if let succeeded = event.succeeded {
                                    label("status", succeeded ? "ok" : "failed")
                                }
                            }
                            .font(AppTypographyTokens.caption)
                            .monospacedDigit()
                            if let errorClass = event.errorClass {
                                Text(errorClass)
                                    .font(AppTypographyTokens.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                Section("Aggregates") {
                    aggregateSection("By Agent", aggregates: payload.byAgent)
                    aggregateSection("By Project", aggregates: payload.byProject)
                    aggregateSection("By Method", aggregates: payload.byMethod)
                    aggregateSection("By Error", aggregates: payload.byErrorClass)
                }
            }
        }
    }

    private var probeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Focused Project", value: acpVibeSpaceContextStore.focusedProjectDisplayName ?? "None")

            if let focusedProjectRootPath = acpVibeSpaceContextStore.focusedProjectRootPath {
                Text(focusedProjectRootPath)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                Picker("Agent", selection: $acpDeveloperToolsService.selectedAgentID) {
                    if acpDeveloperToolsService.availableAgents.isEmpty {
                        Text("No installed ACP agents").tag("")
                    } else {
                        ForEach(acpDeveloperToolsService.availableAgents) { agent in
                            Text(agent.title).tag(agent.id)
                        }
                    }
                }

                Button("Reload") {
                    acpDeveloperToolsService.reloadAgents()
                }
            }

            Toggle("Auto-allow permissions", isOn: $acpDeveloperToolsService.autoAllowPermissions)

            HStack {
                Button(acpDeveloperToolsService.isConnected ? "Reconnect" : "Connect") {
                    Task { await acpDeveloperToolsService.connect() }
                }
                .disabled(
                    acpDeveloperToolsService.isConnecting
                        || acpDeveloperToolsService.selectedAgentID.isEmpty
                        || acpVibeSpaceContextStore.focusedProject == nil
                )

                Button("Disconnect") {
                    acpDeveloperToolsService.disconnect()
                }
                .disabled(!acpDeveloperToolsService.isConnected && !acpDeveloperToolsService.isConnecting)

                Spacer()

                Text(acpDeveloperToolsService.statusText)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Prompt", text: $acpDeveloperToolsService.promptText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)

            HStack {
                Button("Send") {
                    Task { await acpDeveloperToolsService.sendPrompt() }
                }
                .disabled(
                    !acpDeveloperToolsService.isConnected
                        || acpDeveloperToolsService.isSending
                        || acpDeveloperToolsService.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                Button("Cancel") {
                    Task { await acpDeveloperToolsService.cancelPrompt() }
                }
                .disabled(!acpDeveloperToolsService.isSending)
            }

            TextEditor(text: $acpDeveloperToolsService.responseText)
                .font(AppTypographyTokens.captionMonospaced)
                .frame(minHeight: 140)
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ seconds: Double) -> String {
        String(format: "%.1f ms", seconds * 1000)
    }

    private func aggregateSection(_ title: String, aggregates: [String: ACPObservedAggregate]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppTypographyTokens.headline)
            ForEach(aggregates.values.sorted { $0.totalDuration > $1.totalDuration }, id: \.key) { aggregate in
                HStack(spacing: 12) {
                    Text(aggregate.key)
                        .fontWeight(.medium)
                    label("count", "\(aggregate.count)")
                    label("avg", formatDuration(aggregate.averageDuration))
                    label("max", formatDuration(aggregate.maxDuration))
                    if aggregate.failureCount > 0 {
                        label("fail", "\(aggregate.failureCount)")
                            .foregroundStyle(.red)
                    }
                }
                .font(AppTypographyTokens.caption)
                .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

    private func label(_ title: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text(title + ":").foregroundStyle(.secondary)
            Text(value)
        }
    }

    @State private var remoteEvents: [DiagnosticsEventRecord] = []
    @State private var authEvents: [DiagnosticsEventRecord] = []
    @State private var externalSessionEvents: [DiagnosticsEventRecord] = []

    private var remoteDiagnostics: some View {
        diagnosticsEventList(
            events: remoteEvents,
            emptyMessage: "No remote events recorded yet."
        )
        .onAppear {
            remoteEvents = AppDiagnostics.eventStore.snapshot().filter { $0.category == "remote" }
        }
    }

    private var authDiagnostics: some View {
        diagnosticsEventList(
            events: authEvents,
            emptyMessage: "No auth events recorded yet."
        )
        .onAppear {
            authEvents = AppDiagnostics.eventStore.snapshot().filter { $0.category == "auth" }
        }
    }

    private var externalSessionDiagnostics: some View {
        diagnosticsEventList(
            events: externalSessionEvents,
            emptyMessage: "No external session events recorded yet."
        )
        .onAppear {
            externalSessionEvents = AppDiagnostics.eventStore.snapshot().filter { $0.category == "external.sessions" }
        }
    }

    private func diagnosticsEventList(events: [DiagnosticsEventRecord], emptyMessage: String) -> some View {
        List {
            if events.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .font(AppTypographyTokens.callout)
            } else {
                ForEach(Array(events.reversed().enumerated()), id: \.offset) { _, record in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(record.event).fontWeight(.medium).lineLimit(1)
                            Spacer()
                            Text(record.level)
                                .font(AppTypographyTokens.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(record.level == "error" ? Color.red.opacity(0.2) : Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        if !record.metadata.isEmpty {
                            Text(record.metadata.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                                .font(AppTypographyTokens.caption2Monospaced)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                        Text(record.timestamp)
                            .font(AppTypographyTokens.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func statusDot(_ title: String, _ active: Bool) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(active ? .green : .gray.opacity(0.4))
                .frame(width: 6, height: 6)
            Text(title).font(AppTypographyTokens.caption).foregroundStyle(.secondary)
        }
    }

    private func developerToolsStatusRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypographyTokens.headline)
            Text(detail)
                .font(AppTypographyTokens.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}
