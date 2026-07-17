import Foundation

/// Localize a String-typed user-visible text. SwiftUI's LocalizedStringKey
/// handles literals in Text/Button/etc. automatically; these helpers cover
/// the places that build plain Strings (status messages, menu items,
/// formatted summaries). Keys are the English texts, so English is the
/// natural fallback when no translation exists.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}
