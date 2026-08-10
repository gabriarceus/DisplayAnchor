import Foundation
import MenuBarKit

extension Bundle {
    /// The app's resource bundle (localizations), preferring the copy shipped
    /// in Contents/Resources over `Bundle.module`.
    static let appResources = Bundle.resourceBundle(
        named: "DisplayAnchor_DisplayAnchor",
        fallback: .module
    )
}
