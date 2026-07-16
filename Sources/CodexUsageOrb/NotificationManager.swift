import Foundation
import UserNotifications

final class NotificationManager {
    private let center = UNUserNotificationCenter.current()
    private let launchedAt = Date()
    private var deliveredTaskIDs = Set<String>()

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func handle(_ snapshot: ActivitySnapshot) {
        guard let task = snapshot.recentFinishedTask,
              let completedAt = task.completedAt,
              completedAt >= launchedAt,
              !deliveredTaskIDs.contains(task.id)
        else { return }

        deliveredTaskIDs.insert(task.id)
        let content = UNMutableNotificationContent()
        content.title = task.state == .completed ? "Codex 任务已完成" : "Codex 任务已中断"
        content.body = "\(task.title) · 用时 \(duration(task.elapsed))"
        content.sound = .default
        content.userInfo = ["thread_id": task.threadID]

        let request = UNNotificationRequest(identifier: task.id, content: content, trigger: nil)
        center.add(request)
    }

    private func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        if seconds >= 3_600 { return "\(seconds / 3_600)小时\((seconds % 3_600) / 60)分" }
        if seconds >= 60 { return "\(seconds / 60)分\(seconds % 60)秒" }
        return "\(seconds)秒"
    }
}
