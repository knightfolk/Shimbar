import SwiftUI

struct RouterStatsTab: View {
    @State private var statsManager = RouterStatsManager.shared
    @State private var logCollector = ShimLogStatsCollector.shared
    @State private var showClearConfirmation = false

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                shimModelStatsSection

                if !summary.destinationCounts.isEmpty {
                    destinationBreakdown
                }

                recentEntriesSection

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            statsManager = RouterStatsManager.shared
            logCollector = ShimLogStatsCollector.shared
            logCollector.parseLog()
        }
    }

    private var summary: RouterStatsSummary {
        statsManager.getSummary()
    }

    private var logSummary: ShimModelStatsSummary {
        logCollector.getSummary()
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Router Stats")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    logCollector.parseLog()
                    statsManager = RouterStatsManager.shared
                    logCollector = ShimLogStatsCollector.shared
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Refresh stats from shim log")

                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Clear all router statistics")
                .alert("Clear Stats?", isPresented: $showClearConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Clear", role: .destructive) {
                        statsManager.clearStats()
                        logCollector.clearStats()
                    }
                } message: {
                    Text("This will permanently delete all recorded router statistics and shim log stats.")
                }
            }

            Text("Aggregated statistics for model usage and auto router decisions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shim Model Stats

    private var shimModelStatsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model Usage (from shim.log)")
                .font(.body)
                .fontWeight(.medium)

            if logSummary.totalRequests == 0 {
                Text("No requests found in shim.log. Make sure the shim is running and processing requests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                HStack(spacing: 16) {
                    shimStatCard(title: "Total Requests", value: "\(logSummary.totalRequests)", icon: "paperplane")
                    shimStatCard(title: "Auto Router %", value: String(format: "%.0f%%", logSummary.autoRouterPercentage * 100), icon: "arrow.triangle.branch")
                    shimStatCard(title: "Direct %", value: String(format: "%.0f%%", (1.0 - logSummary.autoRouterPercentage) * 100), icon: "arrow.right")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))

                shimModelBreakdown
            }
        }
    }

    private func shimStatCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shimModelBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            let maxCount = logSummary.modelCounts.values.max() ?? 1
            let sorted = logSummary.modelCounts.sorted { $0.value > $1.value }

            ForEach(sorted, id: \.key) { model, count in
                HStack(spacing: 8) {
                    Text(model)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .frame(minWidth: 150, alignment: .leading)
                        .help(model)
                        .foregroundStyle(model.hasPrefix("codex-auto") ? Color.accentColor : .primary)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(model.hasPrefix("codex-auto") ? Color.accentColor.opacity(0.5) : Color.blue.opacity(0.5))
                            .frame(width: max(geo.size.width * CGFloat(count) / CGFloat(maxCount), 2))
                    }
                    .frame(height: 16)

                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)

                    Text(String(format: "%.0f%%", Double(count) / Double(logSummary.totalRequests) * 100))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 35, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Destination Breakdown

    private var destinationBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destination Breakdown")
                .font(.body)
                .fontWeight(.medium)

            let maxCount = summary.destinationCounts.values.max() ?? 1

            ForEach(sortedDestinations, id: \.key) { destination, count in
                HStack(spacing: 8) {
                    Text(destination)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .frame(minWidth: 120, alignment: .leading)
                        .help(destination)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor.opacity(0.7))
                            .frame(width: max(geo.size.width * CGFloat(count) / CGFloat(maxCount), 2))
                    }
                    .frame(height: 16)

                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .padding(10)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    private var sortedDestinations: [(key: String, value: Int)] {
        summary.destinationCounts.sorted { $0.value > $1.value }
    }

    // MARK: - Recent Entries

    private var recentEntriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Routing Decisions")
                .font(.body)
                .fontWeight(.medium)

            let entries = statsManager.getRecentEntries(limit: 20)

            if entries.isEmpty {
                Text("No routing decisions recorded yet. Enable the auto router and process some tasks to see stats here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                entriesTable(entries)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    private func entriesTable(_ entries: [RouterUsageEntry]) -> some View {
        Table(entries) {
            TableColumn("Time") { entry in
                timeCell(entry)
            }
            .width(min: 130, ideal: 140)

            TableColumn("Destination") { entry in
                destinationCell(entry)
            }
            .width(min: 120, ideal: 140)

            TableColumn("Reason") { entry in
                reasonCell(entry)
            }
            .width(min: 90, ideal: 100)

            TableColumn("Confidence") { entry in
                confidenceText(for: entry)
            }
            .width(min: 70, ideal: 75)

            TableColumn("Classifier") { entry in
                classifierCell(entry)
            }
            .width(min: 80, ideal: 100)
        }
        .tableStyle(.bordered)
        .frame(minHeight: 200)
    }

    private func timeCell(_ entry: RouterUsageEntry) -> some View {
        Text(dateFormatter.string(from: entry.timestamp))
            .font(.caption)
            .monospacedDigit()
    }

    private func destinationCell(_ entry: RouterUsageEntry) -> some View {
        Text(entry.selectedDestination)
            .font(.caption)
            .lineLimit(1)
            .help(entry.selectedDestination)
    }

    private func reasonCell(_ entry: RouterUsageEntry) -> some View {
        Text(entry.reason.rawValue.replacingOccurrences(of: "_", with: " "))
            .font(.caption)
            .foregroundStyle(reasonColor(entry.reason))
    }

    private func classifierCell(_ entry: RouterUsageEntry) -> some View {
        Text(entry.classifierUsed.isEmpty ? "—" : entry.classifierUsed)
            .font(.caption)
    }

    private func confidenceText(for entry: RouterUsageEntry) -> some View {
        if entry.reason == .cacheHit || entry.reason == .disabled || entry.reason == .shimOffline {
            return AnyView(Text("—").font(.caption).foregroundStyle(.secondary))
        }
        let formatted = String(format: "%.2f", entry.confidence)
        return AnyView(Text(formatted).font(.caption).monospacedDigit())
    }

    private func reasonColor(_ reason: RouterDecisionReason) -> Color {
        switch reason {
        case .classified: .green
        case .cacheHit: .blue
        case .lowConfidence: .orange
        case .disabled, .shimOffline, .classifierMissing: .secondary
        case .parseError: .red
        case .unknown: .secondary
        }
    }
}
