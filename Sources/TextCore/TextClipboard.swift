import Foundation

/// Port of `simple_clipboard_t` (editor/src/clipboard.cc): an ordered clipboard
/// stack with a movable index for cycling previous/current/next entries.
public final class Clipboard {
    private var stack: [String] = []
    private var index = 0

    public init() {}

    public var isEmpty: Bool { stack.isEmpty }

    /// Append `content` and make it the current entry (push_back in the C++).
    public func push(_ content: String) {
        stack.append(content)
        index = stack.count - 1
    }

    /// The entry at the current index, or nil when the stack is empty.
    public var current: String? {
        index == stack.count ? nil : stack[index]
    }

    /// Step back through history (moves the index; nil when at the oldest entry).
    @discardableResult
    public func previous() -> String? {
        guard index > 0 else { return nil }
        index -= 1
        return stack[index]
    }

    /// Step forward through history (moves the index; nil when at the newest entry).
    @discardableResult
    public func next() -> String? {
        guard index + 1 < stack.count else { return nil }
        index += 1
        return stack[index]
    }
}
