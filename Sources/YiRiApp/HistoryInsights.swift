import Foundation

enum HistoryInsights {
    static func dayGroups(from tasks: [TaskItem]) -> [HistoryDayGroup] {
        let grouped = Dictionary(grouping: sortedCompleted(tasks)) { task in
            task.completedAt?.startOfLocalDay
        }
        return grouped
            .map { HistoryDayGroup(day: $0.key, tasks: $0.value) }
            .sorted { ($0.day ?? .distantPast) > ($1.day ?? .distantPast) }
    }

    static func topics(from tasks: [TaskItem]) -> [HistoryTopic] {
        let completed = sortedCompleted(tasks)
        let manualBuckets = Dictionary(grouping: completed.filter { $0.historyGroupID != nil }) {
            $0.historyGroupID!
        }
        var result = manualBuckets.map { groupID, members in
            let name = members
                .compactMap(\.historyGroupName)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? fallbackName(for: members)
            return HistoryTopic(
                id: "manual-\(groupID.uuidString)",
                name: name,
                tasks: sortedCompleted(members),
                manualGroupID: groupID
            )
        }

        let automaticTasks = completed.filter { $0.historyGroupID == nil }
        var unionFind = UnionFind(count: automaticTasks.count)
        if automaticTasks.count > 1 {
            for left in 0..<(automaticTasks.count - 1) {
                for right in (left + 1)..<automaticTasks.count where titlesAreSimilar(
                    automaticTasks[left].title,
                    automaticTasks[right].title
                ) {
                    unionFind.union(left, right)
                }
            }
        }

        var automaticBuckets: [Int: [TaskItem]] = [:]
        for (index, task) in automaticTasks.enumerated() {
            automaticBuckets[unionFind.root(of: index), default: []].append(task)
        }
        result.append(contentsOf: automaticBuckets.values.map { members in
            let sortedIDs = members.map { $0.id.uuidString }.sorted().joined(separator: "-")
            return HistoryTopic(
                id: "auto-\(sortedIDs)",
                name: automaticName(for: members),
                tasks: sortedCompleted(members),
                manualGroupID: nil
            )
        })

        return result.sorted { left, right in
            let leftDate = left.latestCompletedAt ?? .distantPast
            let rightDate = right.latestCompletedAt ?? .distantPast
            if leftDate != rightDate { return leftDate > rightDate }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    static func titlesAreSimilar(_ left: String, _ right: String) -> Bool {
        let leftTitle = NormalizedTitle(left)
        let rightTitle = NormalizedTitle(right)
        guard !leftTitle.compact.isEmpty, !rightTitle.compact.isEmpty else { return false }
        if leftTitle.compact == rightTitle.compact { return true }

        let prefix = commonPrefix(leftTitle.compact, rightTitle.compact)
        if isMeaningful(prefix), !genericTerms.contains(prefix) { return true }

        let sharedTokens = leftTitle.tokens.intersection(rightTitle.tokens).subtracting(genericTerms)
        let minimumTokenCount = min(leftTitle.tokens.count, rightTitle.tokens.count)
        if minimumTokenCount > 0 {
            let coverage = Double(sharedTokens.count) / Double(minimumTokenCount)
            if sharedTokens.count >= 2, coverage >= 0.5 { return true }
            if sharedTokens.count == 1,
               coverage >= 0.5,
               sharedTokens.contains(where: isMeaningful) {
                return true
            }
        }

        return bigramDice(leftTitle.compact, rightTitle.compact) >= 0.62
    }

    private static let genericTerms: Set<String> = [
        "任务", "处理", "完成", "继续", "今天", "今日", "工作", "优化", "更新"
    ]

    private static func sortedCompleted(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { left, right in
            switch (left.completedAt, right.completedAt) {
            case let (leftDate?, rightDate?):
                if leftDate != rightDate { return leftDate > rightDate }
                return left.createdAt > right.createdAt
            case (nil, nil):
                return left.createdAt > right.createdAt
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
        }
    }

    private static func automaticName(for tasks: [TaskItem]) -> String {
        let normalized = tasks.map { NormalizedTitle($0.title) }
        guard let first = normalized.first else { return "未命名事项" }

        let prefix = normalized.dropFirst().reduce(first.compact) {
            commonPrefix($0, $1.compact)
        }
        if isMeaningful(prefix), !genericTerms.contains(prefix) {
            return prefix
        }

        let commonTokens = normalized.dropFirst().reduce(first.tokens) {
            $0.intersection($1.tokens)
        }.subtracting(genericTerms)
        if !commonTokens.isEmpty {
            let ordered = first.orderedTokens.filter { commonTokens.contains($0) }
            if !ordered.isEmpty { return ordered.joined(separator: " ") }
        }
        return fallbackName(for: tasks)
    }

    private static func fallbackName(for tasks: [TaskItem]) -> String {
        tasks.sorted { left, right in
            let leftCount = left.title.count
            let rightCount = right.title.count
            if leftCount != rightCount { return leftCount < rightCount }
            return (left.completedAt ?? .distantPast) > (right.completedAt ?? .distantPast)
        }.first?.title ?? "未命名事项"
    }

    private static func commonPrefix(_ left: String, _ right: String) -> String {
        String(zip(left, right).prefix { $0 == $1 }.map(\.0))
    }

    private static func isMeaningful(_ value: String) -> Bool {
        let characters = Array(value)
        let hanCount = value.unicodeScalars.count(where: isHan)
        if hanCount >= 2 { return true }
        if hanCount >= 1, characters.count >= 3 { return true }
        return characters.count >= 4
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    private static func bigramDice(_ left: String, _ right: String) -> Double {
        let leftPairs = bigrams(left)
        let rightPairs = bigrams(right)
        guard !leftPairs.isEmpty, !rightPairs.isEmpty else { return 0 }
        let overlap = leftPairs.intersection(rightPairs).count
        return Double(2 * overlap) / Double(leftPairs.count + rightPairs.count)
    }

    private static func bigrams(_ value: String) -> Set<String> {
        let characters = Array(value)
        guard characters.count >= 2 else { return [] }
        return Set((0..<(characters.count - 1)).map {
            String(characters[$0...($0 + 1)])
        })
    }
}

private struct NormalizedTitle {
    let compact: String
    let tokens: Set<String>
    let orderedTokens: [String]

    init(_ value: String) {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "zh_CN")
        ).lowercased()
        var separated = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                separated.unicodeScalars.append(scalar)
            } else {
                separated.append(" ")
            }
        }
        let parts = separated.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        orderedTokens = parts
        tokens = Set(parts)
        compact = parts.joined()
    }
}

private struct UnionFind {
    private var parents: [Int]

    init(count: Int) {
        parents = Array(0..<count)
    }

    mutating func root(of value: Int) -> Int {
        guard parents[value] != value else { return value }
        parents[value] = root(of: parents[value])
        return parents[value]
    }

    mutating func union(_ left: Int, _ right: Int) {
        let leftRoot = root(of: left)
        let rightRoot = root(of: right)
        if leftRoot != rightRoot { parents[rightRoot] = leftRoot }
    }
}
