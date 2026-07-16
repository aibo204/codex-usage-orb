import Foundation

enum CodexTaskState: String {
    case working
    case completed
    case interrupted
}

struct CodexTaskActivity: Identifiable {
    let id: String
    let threadID: String
    let turnID: String
    var title: String
    var state: CodexTaskState
    var statusText: String
    var startedAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var finalMessage: String?

    var elapsed: TimeInterval {
        (completedAt ?? Date()).timeIntervalSince(startedAt)
    }
}

struct ActivitySnapshot {
    var activeTasks: [CodexTaskActivity] = []
    var recentFinishedTask: CodexTaskActivity?

    static let empty = ActivitySnapshot()
}

final class ActivityReader {
    private final class Cursor {
        let url: URL
        let threadID: String
        var offset: UInt64 = 0
        var partial = Data()
        var currentTask: CodexTaskActivity?
        var recentFinishedTask: CodexTaskActivity?

        init(url: URL, threadID: String) {
            self.url = url
            self.threadID = threadID
        }
    }

    private let fileManager = FileManager.default
    private let sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)
    private let sessionIndex = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/session_index.jsonl")
    private var cursors: [String: Cursor] = [:]
    private var titles: [String: String] = [:]
    private var lastTitleRefresh = Date.distantPast
    private var cachedSessionFiles: [URL] = []
    private var lastFileScan = Date.distantPast

    func poll() -> ActivitySnapshot {
        refreshTitlesIfNeeded()
        let urls = recentSessionFiles()

        for url in urls {
            let path = url.path
            let cursor: Cursor
            if let existing = cursors[path] {
                cursor = existing
            } else {
                let threadID = threadIDFromFilename(url) ?? UUID().uuidString
                cursor = Cursor(url: url, threadID: threadID)
                cursors[path] = cursor
            }
            readNewEvents(into: cursor)
            applyTitle(to: cursor)
        }

        let retainedPaths = Set(urls.map(\.path))
        cursors = cursors.filter { retainedPaths.contains($0.key) }

        let active = cursors.values
            .compactMap(\.currentTask)
            .filter { $0.state == .working }
            .sorted { $0.updatedAt > $1.updatedAt }

        let finished = cursors.values
            .compactMap(\.recentFinishedTask)
            .filter { task in
                guard let completedAt = task.completedAt else { return false }
                return Date().timeIntervalSince(completedAt) < 12
            }
            .max { $0.updatedAt < $1.updatedAt }

        return ActivitySnapshot(activeTasks: active, recentFinishedTask: finished)
    }

    private func recentSessionFiles() -> [URL] {
        if Date().timeIntervalSince(lastFileScan) < 2, !cachedSessionFiles.isEmpty {
            return cachedSessionFiles
        }
        guard let enumerator = fileManager.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [(URL, Date)] = []
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values?.contentModificationDate, modified >= cutoff {
                files.append((url, modified))
            }
        }
        cachedSessionFiles = files.sorted { $0.1 > $1.1 }.prefix(24).map(\.0)
        lastFileScan = Date()
        return cachedSessionFiles
    }

    private func readNewEvents(into cursor: Cursor) {
        guard let handle = try? FileHandle(forReadingFrom: cursor.url) else { return }
        defer { try? handle.close() }

        let end = (try? handle.seekToEnd()) ?? 0
        if end < cursor.offset {
            cursor.offset = 0
            cursor.partial = Data()
            cursor.currentTask = nil
            cursor.recentFinishedTask = nil
        }

        var skipFirstPartialLine = false
        if cursor.offset == 0 && end > 16 * 1024 * 1024 {
            cursor.offset = end - 16 * 1024 * 1024
            skipFirstPartialLine = true
        }
        guard end > cursor.offset else { return }

        try? handle.seek(toOffset: cursor.offset)
        let newData = handle.readDataToEndOfFile()
        cursor.offset = end

        var combined = cursor.partial
        combined.append(newData)
        guard let text = String(data: combined, encoding: .utf8) else {
            cursor.partial = Data()
            return
        }

        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if skipFirstPartialLine && !lines.isEmpty { lines.removeFirst() }

        if !text.hasSuffix("\n"), let last = lines.popLast() {
            cursor.partial = Data(last.utf8)
        } else {
            cursor.partial = Data()
        }

        for line in lines {
            process(line: line, cursor: cursor)
        }
    }

    private func process(line: String, cursor: Cursor) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any]
        else { return }

        let outerType = object["type"] as? String ?? ""
        let type = payload["type"] as? String ?? ""
        let timestamp = parseDate(object["timestamp"]) ?? Date()

        if outerType == "event_msg" {
            switch type {
            case "task_started":
                let turnID = payload["turn_id"] as? String ?? UUID().uuidString
                cursor.currentTask = CodexTaskActivity(
                    id: "\(cursor.threadID)-\(turnID)",
                    threadID: cursor.threadID,
                    turnID: turnID,
                    title: titles[cursor.threadID] ?? "Codex 任务",
                    state: .working,
                    statusText: "正在分析任务",
                    startedAt: timestamp,
                    updatedAt: timestamp,
                    completedAt: nil,
                    finalMessage: nil
                )

            case "agent_message":
                guard payload["phase"] as? String == "commentary",
                      var task = cursor.currentTask,
                      task.state == .working,
                      let message = payload["message"] as? String
                else { return }
                let status = sanitize(message)
                if !status.isEmpty { task.statusText = status }
                task.updatedAt = timestamp
                cursor.currentTask = task

            case "agent_reasoning":
                updateStatus("正在分析问题", at: timestamp, cursor: cursor)

            case "patch_apply_end":
                updateStatus((payload["success"] as? Bool) == false ? "代码修改遇到问题" : "正在修改代码", at: timestamp, cursor: cursor)

            case "web_search_end":
                updateStatus("正在整理搜索结果", at: timestamp, cursor: cursor)

            case "image_generation_end":
                updateStatus("正在处理生成的图像", at: timestamp, cursor: cursor)

            case "task_complete":
                guard var task = cursor.currentTask else { return }
                task.state = .completed
                task.statusText = "任务已完成"
                task.completedAt = parseDate(payload["completed_at"]) ?? timestamp
                task.updatedAt = timestamp
                if let final = payload["last_agent_message"] as? String {
                    task.finalMessage = sanitize(final)
                }
                cursor.recentFinishedTask = task
                cursor.currentTask = nil

            case "turn_aborted":
                guard var task = cursor.currentTask else { return }
                task.state = .interrupted
                task.statusText = "任务已中断"
                task.completedAt = timestamp
                task.updatedAt = timestamp
                cursor.recentFinishedTask = task
                cursor.currentTask = nil

            default:
                break
            }
        } else if outerType == "response_item" && (type == "function_call" || type == "custom_tool_call") {
            let name = payload["name"] as? String ?? ""
            let input = String(describing: payload["input"] ?? payload["arguments"] ?? "")
            updateStatus(toolStatus(name: name, input: input), at: timestamp, cursor: cursor)
        }
    }

    private func updateStatus(_ status: String, at date: Date, cursor: Cursor) {
        guard !status.isEmpty, var task = cursor.currentTask, task.state == .working else { return }
        task.statusText = status
        task.updatedAt = date
        cursor.currentTask = task
    }

    private func toolStatus(name: String, input: String) -> String {
        let tool = name.lowercased()
        let arguments = input.lowercased()
        if tool.contains("apply_patch") || arguments.contains("tools.apply_patch") { return "正在修改代码" }
        if tool.contains("view_image") || tool.contains("screenshot") { return "正在检查界面" }
        if tool.contains("imagegen") || tool.contains("image_generation") { return "正在生成图像" }
        if tool.contains("web") || tool.contains("search") { return "正在搜索资料" }
        if tool == "wait" || tool.hasSuffix("__wait") { return "正在等待外部操作" }
        if arguments.contains("xcodebuild") || arguments.contains("swift test") || arguments.contains("./build-app.sh") { return "正在运行验证" }
        if tool.contains("exec") || tool.contains("command") { return "正在执行命令" }
        return "正在处理任务"
    }

    private func sanitize(_ message: String) -> String {
        var value = message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        value = value.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^\)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"/Users/[^\s]+"#,
            with: "本地文件",
            options: .regularExpression
        )
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "#*- "))

        if let boundary = value.firstIndex(where: { "。！？.!?".contains($0) }) {
            value = String(value[...boundary])
        }
        if value.count > 72 {
            value = String(value.prefix(72)) + "…"
        }
        return value
    }

    private func refreshTitlesIfNeeded() {
        guard Date().timeIntervalSince(lastTitleRefresh) > 5,
              let text = try? String(contentsOf: sessionIndex, encoding: .utf8)
        else { return }

        var updated: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = item["id"] as? String,
                  let name = item["thread_name"] as? String
            else { continue }
            updated[id] = name
        }
        titles = updated
        lastTitleRefresh = Date()
    }

    private func applyTitle(to cursor: Cursor) {
        guard let title = titles[cursor.threadID] else { return }
        if var task = cursor.currentTask {
            task.title = title
            cursor.currentTask = task
        }
        if var task = cursor.recentFinishedTask {
            task.title = title
            cursor.recentFinishedTask = task
        }
    }

    private func threadIDFromFilename(_ url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        let pattern = #"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range(at: 1), in: name)
        else { return nil }
        return String(name[range])
    }

    private func parseDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        guard let string = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
