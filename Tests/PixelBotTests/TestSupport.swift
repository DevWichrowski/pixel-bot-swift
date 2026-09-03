import Foundation

@discardableResult
func it<T>(_ description: String, _ body: () throws -> T) rethrows -> T {
    _ = description
    return try body()
}

final class LockedCounter {
    private let lock = NSLock()
    private var storedValue = 0

    func increment() {
        lock.lock()
        storedValue += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }
}
