import Foundation

protocol HeapPrioritizable {
    /// Whether this element should be popped before `other`. Implementations decide
    /// the ordering (max- or min-first) and must break ties deterministically when
    /// the search relies on reproducible expansion order.
    func takesPriority(over other: Self) -> Bool
}

/// Array-backed binary heap shared by the search planners; pops the element that
/// `takesPriority(over:)` every other element.
struct BinaryHeap<Element: HeapPrioritizable> {
    private var entries: [Element] = []

    mutating func push(_ entry: Element) {
        entries.append(entry)
        var child = entries.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard entries[child].takesPriority(over: entries[parent]) else { break }
            entries.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> Element? {
        guard let top = entries.first else { return nil }
        let last = entries.removeLast()
        if !entries.isEmpty {
            entries[0] = last
            var parent = 0
            while true {
                let left = parent * 2 + 1
                let right = left + 1
                var candidate = parent
                if left < entries.count, entries[left].takesPriority(over: entries[candidate]) {
                    candidate = left
                }
                if right < entries.count, entries[right].takesPriority(over: entries[candidate]) {
                    candidate = right
                }
                guard candidate != parent else { break }
                entries.swapAt(parent, candidate)
                parent = candidate
            }
        }
        return top
    }
}
