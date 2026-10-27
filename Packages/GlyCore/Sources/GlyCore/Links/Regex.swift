import Foundation

public extension NSRegularExpression {
    /// A pattern written in the source: an invalid one is a programming error, caught by the first test run.
    static func constant(_ pattern: String, options: Options = []) -> NSRegularExpression {
        do { return try NSRegularExpression(pattern: pattern, options: options) } catch {
            preconditionFailure("invalid pattern \(pattern): \(error)")
        }
    }
}
