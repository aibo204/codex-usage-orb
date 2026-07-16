import Foundation

struct UsageSnapshot {
    var sessionTokens = 0
    var inputTokens = 0
    var outputTokens = 0
    var cachedTokens = 0
    var primaryUsed: Double?
    var secondaryUsed: Double?
    var primaryReset: Date?
    var secondaryReset: Date?
    var primaryWindowMinutes: Int?
    var secondaryWindowMinutes: Int?
    var creditBalance: Double?
    var hasCredits = false
    var unlimited = false
    var plan: String?
    var sourceDate: Date?

    var remaining: Double { max(0, 100 - (primaryUsed ?? 0)) }
}

enum UsageReader {
    static func latest() -> UsageSnapshot? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var candidates: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let date = values?.contentModificationDate {
                candidates.append((url, date))
            }
        }

        for (url, modified) in candidates.sorted(by: { $0.1 > $1.1 }).prefix(20) {
            if let snapshot = parseTail(url: url, modified: modified) { return snapshot }
        }
        return nil
    }

    private static func parseTail(url: URL, modified: Date) -> UsageSnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let end = (try? handle.seekToEnd()) ?? 0
        let tailSize: UInt64 = min(end, 512 * 1024)
        try? handle.seek(toOffset: end - tailSize)
        guard let text = String(data: handle.readDataToEndOfFile(), encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = json["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any]
            else { continue }

            var result = UsageSnapshot()
            result.sessionTokens = int(total["total_tokens"])
            result.inputTokens = int(total["input_tokens"])
            result.outputTokens = int(total["output_tokens"])
            result.cachedTokens = int(total["cached_input_tokens"])
            result.sourceDate = modified

            if let limits = payload["rate_limits"] as? [String: Any] {
                if let primary = limits["primary"] as? [String: Any] {
                    result.primaryUsed = double(primary["used_percent"])
                    result.primaryWindowMinutes = optionalInt(primary["window_minutes"])
                    result.primaryReset = date(primary["resets_at"])
                }
                if let secondary = limits["secondary"] as? [String: Any] {
                    result.secondaryUsed = double(secondary["used_percent"])
                    result.secondaryWindowMinutes = optionalInt(secondary["window_minutes"])
                    result.secondaryReset = date(secondary["resets_at"])
                }
                if let credits = limits["credits"] as? [String: Any] {
                    result.hasCredits = credits["has_credits"] as? Bool ?? false
                    result.unlimited = credits["unlimited"] as? Bool ?? false
                    result.creditBalance = double(credits["balance"])
                }
                result.plan = limits["plan_type"] as? String
            }
            return result
        }
        return nil
    }

    private static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    private static func optionalInt(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func date(_ value: Any?) -> Date? {
        guard let seconds = (value as? NSNumber)?.doubleValue else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
