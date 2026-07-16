import AppKit
import QuartzCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSWindow!
    private let model = UsageViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 92, height: 92),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The borderless window's native shadow follows its rectangular backing
        // surface. The SwiftUI glass surface supplies its own shape-aware depth.
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.canBecomeVisibleWithoutLogin = true
        panel.contentView = NSHostingView(rootView: OrbRootView(model: model, resize: resize))

        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 116, y: screen.midY))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        model.start()
        captureForDesignQAIfRequested()
    }

    private func captureForDesignQAIfRequested() {
        let standardExpandedFlag = CommandLine.arguments.firstIndex(of: "--capture")
        let dualExpandedFlag = CommandLine.arguments.firstIndex(of: "--capture-dual")
        let dualCollapsedFlag = CommandLine.arguments.firstIndex(of: "--capture-dual-collapsed")
        let completedFlag = CommandLine.arguments.firstIndex(of: "--capture-completed")
        let dualWindowFlag = dualExpandedFlag ?? dualCollapsedFlag
        let expandedFlag = standardExpandedFlag ?? dualExpandedFlag ?? completedFlag
        let collapsedFlag = CommandLine.arguments.firstIndex(of: "--capture-collapsed") ?? dualCollapsedFlag
        guard let flag = expandedFlag ?? collapsedFlag,
              CommandLine.arguments.indices.contains(flag + 1) else { return }
        let outputPath = CommandLine.arguments[flag + 1]

        if dualWindowFlag != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self = self, var snapshot = self.model.snapshot else { return }
                snapshot.primaryUsed = 18
                snapshot.primaryWindowMinutes = 300
                snapshot.primaryReset = Date().addingTimeInterval(2 * 60 * 60 + 14 * 60)
                snapshot.secondaryUsed = 7
                snapshot.secondaryWindowMinutes = 10_080
                snapshot.secondaryReset = Date().addingTimeInterval(5 * 24 * 60 * 60)
                self.model.snapshot = snapshot
            }
        }

        if completedFlag != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) { [weak self] in
                let finishedAt = Date()
                let task = CodexTaskActivity(
                    id: "design-qa-complete",
                    threadID: "design-qa",
                    turnID: "preview",
                    title: "优化 Codex Usage 悬浮球",
                    state: .completed,
                    statusText: "任务已完成",
                    startedAt: finishedAt.addingTimeInterval(-84),
                    updatedAt: finishedAt,
                    completedAt: finishedAt,
                    finalMessage: nil
                )
                self?.model.activity = ActivitySnapshot(activeTasks: [], recentFinishedTask: task)
            }
        }

        if expandedFlag != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self = self else { return }
                self.model.expanded = true
                self.resize(expanded: true, height: self.desiredExpandedHeight())
            }
        }
        let captureDelay = expandedFlag == nil ? 1.2 : 1.8
        DispatchQueue.main.asyncAfter(deadline: .now() + captureDelay) { [weak self] in
            guard let view = self?.panel.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                NSApp.terminate(nil)
                return
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: outputPath))
            }
            NSApp.terminate(nil)
        }
    }

    private func desiredExpandedHeight() -> CGFloat {
        if !model.activity.activeTasks.isEmpty {
            return model.activity.activeTasks.count > 1 ? min(248, CGFloat(92 + model.activity.activeTasks.prefix(3).count * 52)) : 176
        }
        if model.activity.recentFinishedTask != nil { return 156 }
        return model.snapshot?.secondaryUsed != nil ? 228 : 192
    }

    private func resize(expanded: Bool, height: CGFloat) {
        let size = expanded ? NSSize(width: 316, height: height) : NSSize(width: 92, height: 92)
        let old = panel.frame
        let origin = NSPoint(x: old.maxX - size.width, y: old.maxY - size.height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.36
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(NSRect(origin: origin, size: size), display: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
