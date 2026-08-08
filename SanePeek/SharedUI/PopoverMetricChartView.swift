import SwiftUI

/// The menu bar popup's right-hand detail panel: title, big value, and the selected metric's
/// history chart.
///
/// Renders each metric with the *same* chart the dashboard uses for it — the stacked
/// user/system/idle and App/Wired/Compressed/Free breakdowns, the mirrored network chart, and
/// a sparkline for the metrics whose dashboard card uses one — via the shared chart views, so
/// there's one implementation per shape rather than a second, flatter set living here.
///
/// Deliberately draws no background of its own: `MenuBarExtra(.window)` already provides the
/// popup's Liquid Glass surface, and glass can't sample glass — a second material layered on
/// top reads the frosted panel rather than the desktop and flattens the whole popup. So content
/// sits directly on it and uses vibrancy-aware `.primary`/`.secondary` colors instead, staying
/// legible in both appearances.
struct PopoverMetricChartView: View {
    let model: MetricCardModel
    let viewModel: DashboardViewModel
    let formatter: MetricFormatter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let message = model.unavailableMessage {
                placeholder(message)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityValue(model.accessibilityValue)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.accentColor)
                .frame(width: 8, height: 8)

            Text(model.title)
                .font(.headline)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func placeholder(_ message: String) -> some View {
        Spacer(minLength: 0)
        Text(message)
            .font(MetricTypography.secondaryMetric)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
        Spacer(minLength: 0)
    }

    @ViewBuilder
    private var content: some View {
        if model.id == .storage, let detail = model.storageUsageDetail {
            StorageUsageDetailView(fraction: model.usageFraction, detail: detail, color: model.accentColor, formatter: formatter)
        } else {
            regularContent
        }
    }

    private var regularContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.primaryValue)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: model.primaryValue)

            if model.sparklineValues.isEmpty {
                // Storage/battery never accumulate history (the engine tracks none for
                // them), so only the chart falls back — the value above still shows.
                placeholder("No trend data yet")
            } else {
                chart
                    .frame(maxHeight: .infinity)
                    .frame(minHeight: 110)

                HistoryChartTimeAxis()

                if !legend.isEmpty {
                    legendView
                }
            }
        }
    }

    /// Mirrors the dashboard's choice of chart per metric rather than inventing a popup-only
    /// one, so a metric reads the same in both places.
    @ViewBuilder
    private var chart: some View {
        switch model.id {
        case .cpu:
            // No idle/free remainder band here, unlike the dashboard: at the popup's size
            // it filled most of every bar and crowded the load the chart is actually about.
            // The fixed 0...100% axis still makes the unused headroom readable.
            CPUCardView.chart(for: viewModel.cpuDetail, accentColor: model.accentColor, axisLabel: percentageAxisLabel, showsIdle: false)
        case .memory:
            MemoryCardView.chart(for: viewModel.memoryDetail, accentColor: model.accentColor, axisLabel: percentageAxisLabel, showsFree: false)
        case .network:
            NetworkCardView.chart(for: viewModel.networkDetail, accentColor: model.accentColor, axisLabel: axisLabel)
        case .temperature, .gpu, .storage, .battery:
            // These render as a plain trend on the dashboard too — there's a single value
            // here, not a breakdown that sums to a whole.
            SparklineView(
                values: Array(model.sparklineValues.suffix(MetricChartLayout.historyWindowSize)),
                color: model.accentColor
            )
        }
    }

    private var legendView: some View {
        // Wraps rather than truncating: Memory's four-swatch breakdown doesn't fit the
        // panel's width on one line.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { legendSwatches }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) { legendSwatches }
            }
        }
    }

    private var legendSwatches: some View {
        ForEach(legend) { entry in
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(entry.color)
                    .frame(width: 8, height: 8)
                Text(entry.id)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Swatch labels for the stacked/mirrored charts. Empty for the sparkline metrics,
    /// which have a single unlabeled series. CPU's "Idle" and Memory's "Free" are absent
    /// because this view draws no remainder band for them to label.
    private var legend: [MetricChartSeries] {
        switch model.id {
        case .cpu:
            [
                MetricChartSeries("User", color: model.accentColor, values: []),
                MetricChartSeries("System", color: MetricPalette.cpuSystem, values: [])
            ]
        case .memory:
            [
                MetricChartSeries("App", color: model.accentColor, values: []),
                MetricChartSeries("Wired", color: MetricPalette.memoryWired, values: []),
                MetricChartSeries("Compressed", color: MetricPalette.memoryCompressed, values: [])
            ]
        case .network:
            [
                MetricChartSeries("Download", color: model.accentColor, values: []),
                MetricChartSeries("Upload", color: MetricPalette.networkUpload, values: [])
            ]
        case .temperature, .gpu, .storage, .battery:
            []
        }
    }

    private func axisLabel(_ value: Double) -> String {
        PopoverChartAxis.label(for: value, kind: model.id, formatter: formatter)
    }

    /// CPU/Memory stack on a fixed `0...1` domain, so their gridlines are always the same
    /// quarters regardless of current load.
    private func percentageAxisLabel(_ value: Double) -> String {
        formatter.percentage(value)
    }
}

#Preview("CPU") {
    let appState = AppState(dependencies: .preview)
    return PopoverMetricChartView(
        model: appState.dashboardViewModel.cpuCard,
        viewModel: appState.dashboardViewModel,
        formatter: MetricFormatter()
    )
    .padding()
    .frame(width: 320, height: 280)
}
