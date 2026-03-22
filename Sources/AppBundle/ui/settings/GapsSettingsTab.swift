import Common
import SwiftUI

struct GapsSettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            if viewModel.hasPerMonitorGaps {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Per-monitor gap values detected. Use the text editor for advanced gap configuration.")
                            .font(.callout)
                    }
                }
            }

            Section("Inner Gaps (between windows)") {
                gapStepper("Horizontal", value: $viewModel.innerHorizontal)
                gapStepper("Vertical", value: $viewModel.innerVertical)
            }
            .disabled(viewModel.hasPerMonitorGaps)

            Section("Outer Gaps (monitor edges)") {
                gapStepper("Top", value: $viewModel.outerTop)
                gapStepper("Bottom", value: $viewModel.outerBottom)
                gapStepper("Left", value: $viewModel.outerLeft)
                gapStepper("Right", value: $viewModel.outerRight)
            }
            .disabled(viewModel.hasPerMonitorGaps)

            Section("Preview") {
                GapsDiagram(
                    innerH: viewModel.innerHorizontal,
                    innerV: viewModel.innerVertical,
                    outerTop: viewModel.outerTop,
                    outerBottom: viewModel.outerBottom,
                    outerLeft: viewModel.outerLeft,
                    outerRight: viewModel.outerRight
                )
                .frame(height: 200)
            }
        }
        .formStyle(.grouped)
        .onChange(of: viewModel.innerHorizontal) { _ in viewModel.markChanged() }
        .onChange(of: viewModel.innerVertical) { _ in viewModel.markChanged() }
        .onChange(of: viewModel.outerTop) { _ in viewModel.markChanged() }
        .onChange(of: viewModel.outerBottom) { _ in viewModel.markChanged() }
        .onChange(of: viewModel.outerLeft) { _ in viewModel.markChanged() }
        .onChange(of: viewModel.outerRight) { _ in viewModel.markChanged() }
    }

    @ViewBuilder
    private func gapStepper(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value.wrappedValue)px")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Stepper("", value: value, in: 0...200, step: 1)
                .labelsHidden()
        }
    }
}

// MARK: - Gaps Visual Diagram

struct GapsDiagram: View {
    let innerH: Int
    let innerV: Int
    let outerTop: Int
    let outerBottom: Int
    let outerLeft: Int
    let outerRight: Int

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            // Scale gaps for visualization (max 200px config -> proportional in diagram)
            let maxGap: CGFloat = 200
            let scale = min(width, height) * 0.15 / max(maxGap, 1)

            let oTop = CGFloat(outerTop) * scale
            let oBottom = CGFloat(outerBottom) * scale
            let oLeft = CGFloat(outerLeft) * scale
            let oRight = CGFloat(outerRight) * scale
            let iH = CGFloat(innerH) * scale
            let iV = CGFloat(innerV) * scale

            let monitorPadding: CGFloat = 8

            ZStack {
                // Monitor frame
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 2)

                // Content area (inside outer gaps)
                let contentX = monitorPadding + oLeft
                let contentY = monitorPadding + oTop
                let contentW = width - 2 * monitorPadding - oLeft - oRight
                let contentH = height - 2 * monitorPadding - oTop - oBottom

                if contentW > 0 && contentH > 0 {
                    // Two windows side by side
                    let windowW = (contentW - iH) / 2
                    let windowH = (contentH - iV) / 2

                    // Top-left window
                    if windowW > 0 && windowH > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(width: windowW, height: windowH)
                            .position(x: contentX + windowW / 2, y: contentY + windowH / 2)

                        // Top-right window
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.2))
                            .frame(width: windowW, height: windowH)
                            .position(x: contentX + windowW + iH + windowW / 2, y: contentY + windowH / 2)

                        // Bottom-left window
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.2))
                            .frame(width: windowW, height: windowH)
                            .position(x: contentX + windowW / 2, y: contentY + windowH + iV + windowH / 2)

                        // Bottom-right window
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: windowW, height: windowH)
                            .position(x: contentX + windowW + iH + windowW / 2, y: contentY + windowH + iV + windowH / 2)
                    }

                    // Labels
                    if oTop > 10 {
                        Text("top: \(outerTop)")
                            .font(.system(size: 9).monospaced())
                            .foregroundStyle(.secondary)
                            .position(x: width / 2, y: monitorPadding + oTop / 2)
                    }
                    if oLeft > 10 {
                        Text("\(outerLeft)")
                            .font(.system(size: 9).monospaced())
                            .foregroundStyle(.secondary)
                            .position(x: monitorPadding + oLeft / 2, y: height / 2)
                    }
                    if iH > 10 {
                        Text("\(innerH)")
                            .font(.system(size: 9).monospaced())
                            .foregroundStyle(.secondary)
                            .position(x: contentX + windowW + iH / 2, y: height / 2)
                    }
                }
            }
        }
    }
}
