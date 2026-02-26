import Foundation

/// A value with associated check results, mirroring Go's Checked[T] type.
public struct Checked<T: Sendable>: Sendable {
    public let value: T
    public let checks: [Check]

    public init(value: T, checks: [Check]) {
        self.value = value
        self.checks = checks
    }
}

/// A single check result.
public struct Check: Sendable {
    public let name: String
    public let expression: String
    public let status: String

    public init(name: String, expression: String, status: String) {
        self.name = name
        self.expression = expression
        self.status = status
    }
}
