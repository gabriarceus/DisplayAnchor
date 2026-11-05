import Foundation
import MenuBarKit

extension Localizer {
    /// Localized display count, such as "1 display" or "3 displays".
    func displayCount(_ count: Int) -> String {
        count == 1 ? self("display_count_one", count) : self("display_count_other", count)
    }
}

extension Date {
    /// Abbreviated time between this date and now, formatted for `locale`.
    func relativeText(locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
