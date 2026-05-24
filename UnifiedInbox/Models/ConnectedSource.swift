import Foundation
import SwiftData

@Model
final class ConnectedSource {
    @Attribute(.unique) var id: UUID
    var name: String
    var typeRaw: String
    var isEnabled: Bool
    var configData: Data?
    var lastSyncedAt: Date?

    var type: SourceType {
        get { SourceType(rawValue: typeRaw) ?? .gmail }
        set { typeRaw = newValue.rawValue }
    }

    var gmailConfig: GmailConfig {
        get {
            guard let configData,
                  let decoded = try? JSONDecoder().decode(GmailConfig.self, from: configData) else {
                return GmailConfig()
            }
            return decoded
        }
        set {
            configData = try? JSONEncoder().encode(newValue)
        }
    }

    init(
        id: UUID = UUID(),
        name: String = "Gmail",
        type: SourceType = .gmail,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.isEnabled = isEnabled
    }
}
