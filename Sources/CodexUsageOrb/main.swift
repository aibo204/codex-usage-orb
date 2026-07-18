import AppKit
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
        panel.contentView = NSHostingView(rootView: OrbRootView(model: model))

        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 116, y: screen.midY))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        model.start()
        captureForDesignQAIfRequested()
    }

    private func captureForDesignQAIfRequested() {
        let standardFlag = CommandLine.arguments.firstIndex(of: "--capture")
        let dualFlag = CommandLine.arguments.firstIndex(of: "--capture-dual")
        let dualCollapsedFlag = CommandLine.arguments.firstIndex(of: "--capture-dual-collapsed")
        let completedFlag = CommandLine.arguments.firstIndex(of: "--capture-completed")
        let dualWindowFlag = dualFlag ?? dualCollapsedFlag
        let collapsedFlag = CommandLine.arguments.firstIndex(of: "--capture-collapsed")
        guard let flag = standardFlag ?? dualFlag ?? dualCollapsedFlag ?? completedFlag ?? collapsedFlag,
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

        let captureDelay = completedFlag == nil ? 1.2 : 1.8
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

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
