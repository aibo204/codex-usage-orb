import AppKit
import SwiftUI

final class UsageViewModel: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var activity = ActivitySnapshot.empty
    private var usageTimer: Timer?
    private var activityTimer: Timer?
    private let activityReader = ActivityReader()
    private let activityQueue = DispatchQueue(label: "local.codex.usage-orb.activity", qos: .utility)

    func start() {
        refreshUsage()
        refreshActivity()
        usageTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshUsage()
        }
        activityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshActivity()
        }
    }

    func stop() {
        usageTimer?.invalidate()
        activityTimer?.invalidate()
        usageTimer = nil
        activityTimer = nil
    }

    func refresh() {
        refreshUsage()
        refreshActivity()
    }

    private func refreshUsage() {
        DispatchQueue.global(qos: .utility).async {
            let value = UsageReader.latest()
            DispatchQueue.main.async { self.snapshot = value }
        }
    }

    private func refreshActivity() {
        activityQueue.async { [weak self] in
            guard let self = self else { return }
            let value = self.activityReader.poll()
            DispatchQueue.main.async {
                self.activity = value
            }
        }
    }
}

struct OrbRootView: View {
    @ObservedObject var model: UsageViewModel
    @State private var spinnerRotation = 0.0

    private var orbUsesSecondaryWindow: Bool {
        guard let primaryMinutes = model.snapshot?.primaryWindowMinutes,
              let secondaryMinutes = model.snapshot?.secondaryWindowMinutes,
              model.snapshot?.secondaryUsed != nil else { return false }
        return secondaryMinutes < primaryMinutes
    }

    private var orbRemaining: Double {
        guard let snapshot = model.snapshot else { return 0 }
        let used = orbUsesSecondaryWindow ? snapshot.secondaryUsed : snapshot.primaryUsed
        return max(0, 100 - (used ?? 0))
    }

    private var orbWindowMinutes: Int? {
        guard let snapshot = model.snapshot else { return nil }
        return orbUsesSecondaryWindow ? snapshot.secondaryWindowMinutes : snapshot.primaryWindowMinutes
    }

    private var orbWindowLabel: String {
        guard let minutes = orbWindowMinutes else { return "剩余" }
        return minutes < 10_080 ? "5H 剩余" : "本周剩余"
    }

    var body: some View {
        orbView
            .frame(width: 92, height: 92)
            .contentShape(Circle())
            .contextMenu {
                Button("立即刷新") { model.refresh() }
                Divider()
                Button("退出 Codex Usage Orb") { NSApp.terminate(nil) }
            }
            .onAppear { spinnerRotation = 360 }
    }

    private var orbView: some View {
        ZStack {
            FrostedGlass(material: .popover)
                .clipShape(Circle())
            Circle().fill(Color.white.opacity(0.34))
            Circle()
                .stroke(Color.white.opacity(0.95), lineWidth: 1.5)

            if !model.activity.activeTasks.isEmpty {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(workColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(spinnerRotation))
                    .padding(7)
                    .shadow(color: workColor.opacity(0.24), radius: 3)
                    .animation(.linear(duration: 1.25).repeatForever(autoreverses: false), value: spinnerRotation)

                VStack(spacing: 2) {
                    if model.activity.activeTasks.count > 1 {
                        Text("\(model.activity.activeTasks.count)")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    } else {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 21, weight: .medium))
                    }
                    Text("工作中")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.black.opacity(0.78))
            } else if let task = model.activity.recentFinishedTask {
                Circle()
                    .stroke(finishedColor(for: task).opacity(0.18), lineWidth: 6)
                    .padding(7)
                VStack(spacing: 2) {
                    Image(systemName: task.state == .completed ? "checkmark" : "exclamationmark")
                        .font(.system(size: 24, weight: .semibold))
                    Text(task.state == .completed ? "已完成" : "已中断")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(finishedColor(for: task))
            } else {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(7)
                    .shadow(color: ringColor.opacity(0.24), radius: 3)
                VStack(spacing: -1) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(model.snapshot == nil ? "—" : "\(Int(orbRemaining))")
                            .font(.system(size: 25, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        if model.snapshot != nil {
                            Text("%")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(.black.opacity(0.50))
                        }
                    }
                    Text(orbWindowLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.black.opacity(0.48))
                }
                .foregroundColor(.black.opacity(0.88))
            }
        }
        .frame(width: 82, height: 82)
        .padding(5)
        .help(orbHelp)
    }

    private var orbHelp: String {
        if model.activity.activeTasks.count > 1 {
            return "Codex 正在处理 \(model.activity.activeTasks.count) 个任务"
        }
        if let task = model.activity.activeTasks.first {
            return "\(task.title) · \(task.statusText) · \(elapsedText(task.elapsed))"
        }
        if let task = model.activity.recentFinishedTask {
            let result = task.state == .completed ? "已完成" : "已中断"
            return "\(task.title) · \(result) · 用时 \(elapsedText(task.elapsed))"
        }
        guard model.snapshot != nil else { return "尚未发现 Codex usage 数据 · 右键可刷新或退出" }
        return "\(orbWindowLabel) \(Int(orbRemaining))% · 右键可刷新或退出"
    }

    private var progress: CGFloat {
        CGFloat(min(1, max(0, orbRemaining / 100)))
    }

    private var ringColor: Color { statusColor(forRemaining: orbRemaining) }

    private var workColor: Color {
        Color(red: 0.12, green: 0.48, blue: 0.96)
    }

    private var completionColor: Color {
        Color(red: 0.20, green: 0.78, blue: 0.40)
    }

    private func finishedColor(for task: CodexTaskActivity) -> Color {
        task.state == .completed ? completionColor : .orange
    }

    private func elapsedText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        if seconds >= 3_600 { return "\(seconds / 3_600)h \((seconds % 3_600) / 60)m" }
        if seconds >= 60 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds)s"
    }

    private func statusColor(forRemaining remaining: Double) -> Color {
        if remaining <= 10 { return .red }
        if remaining <= 30 { return .orange }
        return completionColor
    }
}

struct FrostedGlass: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
