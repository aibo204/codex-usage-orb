import AppKit
import SwiftUI

final class UsageViewModel: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var activity = ActivitySnapshot.empty
    @Published var expanded = false
    private var usageTimer: Timer?
    private var activityTimer: Timer?
    private let activityReader = ActivityReader()
    private let activityQueue = DispatchQueue(label: "local.codex.usage-orb.activity", qos: .utility)
    private let notificationManager = NotificationManager()

    func start() {
        notificationManager.requestPermission()
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
                self.notificationManager.handle(value)
            }
        }
    }
}

struct OrbRootView: View {
    @ObservedObject var model: UsageViewModel
    let resize: (Bool, CGFloat) -> Void
    @State private var spinnerRotation = 0.0

    private var hasSecondaryWindow: Bool {
        model.snapshot?.secondaryUsed != nil
    }

    private var detailHeight: CGFloat {
        if !model.activity.activeTasks.isEmpty {
            return model.activity.activeTasks.count > 1 ? min(248, CGFloat(92 + model.activity.activeTasks.prefix(3).count * 52)) : 176
        }
        if model.activity.recentFinishedTask != nil { return 156 }
        return hasSecondaryWindow ? 228 : 192
    }

    private var layoutKey: String {
        if !model.activity.activeTasks.isEmpty { return "working-\(model.activity.activeTasks.count)" }
        if let task = model.activity.recentFinishedTask { return "finished-\(task.id)" }
        return hasSecondaryWindow ? "usage-dual" : "usage-single"
    }

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
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Color.clear

                currentDetailView
                    .opacity(model.expanded ? 1 : 0)
                    .scaleEffect(model.expanded ? 1 : 0.92, anchor: .topTrailing)
                    .allowsHitTesting(model.expanded)

                orbView
                    .opacity(model.expanded ? 0 : 1)
                    .scaleEffect(model.expanded ? 0.88 : 1, anchor: .topTrailing)
                    .allowsHitTesting(!model.expanded)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topTrailing)
            .contentShape(Rectangle())
            .onTapGesture {
                let next = !model.expanded
                withAnimation(.interactiveSpring(response: 0.36, dampingFraction: 0.88, blendDuration: 0.12)) {
                    model.expanded = next
                }
                resize(next, detailHeight)
            }
            .onChange(of: layoutKey) { _ in
                guard model.expanded else { return }
                resize(true, detailHeight)
            }
            .contextMenu {
                Button("立即刷新") { model.refresh() }
                Divider()
                Button("退出 Codex Usage Orb") { NSApp.terminate(nil) }
            }
        }
        .onAppear {
            spinnerRotation = 360
        }
    }

    @ViewBuilder
    private var currentDetailView: some View {
        if !model.activity.activeTasks.isEmpty {
            workingDetailView
        } else if let task = model.activity.recentFinishedTask {
            completionDetailView(task)
        } else {
            usageDetailView
        }
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
                    .trim(from: 0.08, to: 0.78)
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
            } else if model.activity.recentFinishedTask != nil {
                Circle()
                    .stroke(completionColor.opacity(0.18), lineWidth: 6)
                    .padding(7)
                VStack(spacing: 2) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .semibold))
                    Text("已完成")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(completionColor)
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
        .help("Codex 当前限额窗口 · 点击展开 · 右键退出")
    }

    private var workingDetailView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 7) {
                    Circle()
                        .fill(workColor)
                        .frame(width: 7, height: 7)
                    Text(model.activity.activeTasks.count > 1 ? "CODEX TASKS" : "CODEX WORKING")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.8)
                }
                .foregroundColor(.black.opacity(0.70))
                Spacer()
                collapseButton
            }
            .padding(.bottom, 14)

            if model.activity.activeTasks.count == 1, let task = model.activity.activeTasks.first {
                Text(task.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                    .foregroundColor(.black.opacity(0.86))
                    .padding(.bottom, 10)

                HStack(spacing: 7) {
                    Image(systemName: statusIcon(for: task.statusText))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(workColor)
                    Text(task.statusText)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(.black.opacity(0.55))
                    Spacer(minLength: 8)
                    Text(elapsedText(task.elapsed))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.black.opacity(0.42))
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.activity.activeTasks.prefix(3).enumerated()), id: \.element.id) { index, task in
                        if index > 0 {
                            Divider().overlay(Color.black.opacity(0.10))
                        }
                        taskRow(task)
                    }
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .frame(width: 316, height: detailHeight, alignment: .top)
        .background(glassPanelBackground)
        .foregroundColor(.black.opacity(0.88))
    }

    private func completionDetailView(_ task: CodexTaskActivity) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: task.state == .completed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(task.state == .completed ? completionColor : .orange)
                    Text(task.state == .completed ? "CODEX COMPLETE" : "CODEX STOPPED")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.7)
                }
                .foregroundColor(.black.opacity(0.70))
                Spacer()
                collapseButton
            }
            .padding(.bottom, 14)

            Text(task.title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(2)
                .foregroundColor(.black.opacity(0.86))
                .padding(.bottom, 9)

            Text("用时 \(elapsedText(task.elapsed))")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.black.opacity(0.48))
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .frame(width: 316, height: detailHeight, alignment: .top)
        .background(glassPanelBackground)
        .foregroundColor(.black.opacity(0.88))
    }

    private func taskRow(_ task: CodexTaskActivity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(task.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(elapsedText(task.elapsed))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.black.opacity(0.40))
            }
            Text(task.statusText)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .foregroundColor(.black.opacity(0.50))
        }
        .padding(.vertical, 8)
    }

    private var usageDetailView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CODEX USAGE")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(2.1)
                    .foregroundColor(.black.opacity(0.70))
                Spacer()
                collapseButton
            }
            .padding(.bottom, 8)

            if let usage = model.snapshot {
                if usage.primaryUsed != nil {
                    meter(title: windowTitle(usage.primaryWindowMinutes, fallback: "用量窗口"), used: usage.primaryUsed, reset: usage.primaryReset)
                }
                if usage.secondaryUsed != nil {
                    meter(title: windowTitle(usage.secondaryWindowMinutes, fallback: "附加窗口"), used: usage.secondaryUsed, reset: usage.secondaryReset)
                        .padding(.top, 7)
                }

                Divider()
                    .overlay(Color.black.opacity(0.12))
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                HStack(spacing: 0) {
                    stat(title: "会话 TOKENS", value: compact(usage.sessionTokens))
                    verticalDivider
                    stat(title: "输出", value: compact(usage.outputTokens))
                    verticalDivider
                    stat(title: "缓存", value: compact(usage.cachedTokens))
                }

            } else {
                VStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.system(size: 32))
                    Text("还没有发现 Codex usage 数据")
                    Text("运行一次 Codex 任务后会自动出现")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .frame(width: 316, height: detailHeight)
        .background(glassPanelBackground)
        .foregroundColor(.black.opacity(0.88))
    }

    private var collapseButton: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.30))
                .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.8))
                .shadow(color: Color.black.opacity(0.13), radius: 4, x: 0, y: 2)
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.72))
        }
        .frame(width: 30, height: 30)
    }

    private var glassPanelBackground: some View {
        ZStack {
            FrostedGlass(material: .popover)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.28))
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.86), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                .padding(2)
        )
    }

    private func meter(title: String, used: Double?, reset: Date?) -> some View {
        let usedAmount = min(100, max(0, used ?? 0))
        let remainingAmount = 100 - usedAmount
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(remainingAmount))% 剩余")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                if let reset = reset {
                    Text("\(countdown(reset)) 后重置")
                        .font(.system(size: 10))
                        .foregroundColor(.black.opacity(0.43))
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.07))
                        .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 0.5))
                    Capsule().fill(statusColor(forRemaining: remainingAmount))
                        .frame(width: geometry.size.width * CGFloat(remainingAmount / 100))
                }
            }
            .frame(height: 7)
        }
    }

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.black.opacity(0.46))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.13))
            .frame(width: 0.5, height: 42)
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

    private func elapsedText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        if seconds >= 3_600 { return "\(seconds / 3_600)h \((seconds % 3_600) / 60)m" }
        if seconds >= 60 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds)s"
    }

    private func statusIcon(for status: String) -> String {
        if status.contains("代码") { return "chevron.left.forwardslash.chevron.right" }
        if status.contains("命令") || status.contains("验证") { return "terminal" }
        if status.contains("搜索") { return "magnifyingglass" }
        if status.contains("界面") || status.contains("图像") { return "photo" }
        if status.contains("等待") { return "hourglass" }
        return "sparkles"
    }

    private func statusColor(forRemaining remaining: Double) -> Color {
        if remaining <= 10 { return .red }
        if remaining <= 30 { return .orange }
        return Color(red: 0.20, green: 0.78, blue: 0.40)
    }

    private func compact(_ number: Int) -> String {
        if number >= 1_000_000 { return String(format: "%.1fM", Double(number) / 1_000_000) }
        if number >= 1_000 { return String(format: "%.1fK", Double(number) / 1_000) }
        return "\(number)"
    }

    private func windowTitle(_ minutes: Int?, fallback: String) -> String {
        guard let minutes = minutes else { return fallback }
        if minutes >= 10_080 { return "每周窗口" }
        if minutes >= 60 { return "\(minutes / 60) 小时窗口" }
        return "\(minutes) 分钟窗口"
    }

    private func countdown(_ date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        if seconds >= 86_400 { return "\(seconds / 86_400)天\((seconds % 86_400) / 3_600)小时" }
        if seconds >= 3_600 { return "\(seconds / 3_600)小时\((seconds % 3_600) / 60)分" }
        return "\(max(1, seconds / 60))分钟"
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
