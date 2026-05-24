import Foundation
import SwiftUI

enum Formatters {
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func date(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) || Calendar.current.isDateInYesterday(date) {
            return relative.localizedString(for: date, relativeTo: Date())
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

extension ItemPriority {
    var color: Color {
        switch self {
        case .critical: .red
        case .high: .orange
        case .medium: .blue
        case .low: .gray
        }
    }
}
