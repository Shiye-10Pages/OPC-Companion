import Foundation

public struct BannerMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let kind: Kind

    public enum Kind: String, Sendable, CaseIterable {
        case info
        case success
        case warning
        case error
    }

    public init(id: UUID = UUID(), text: String, kind: Kind = .info) {
        self.id = id
        self.text = text
        self.kind = kind
    }
}
