import Foundation

/// Basit iki dilli metin desteği: sistem dili Türkçe ise Türkçe, değilse İngilizce.
enum L10n {
    static let isTurkish: Bool = Locale.preferredLanguages.first?.lowercased().hasPrefix("tr") ?? false

    static var locale: Locale { Locale(identifier: isTurkish ? "tr_TR" : "en_US") }

    /// İngilizce ve Türkçe karşılıklardan uygun olanı döner.
    static func t(_ english: String, _ turkish: String) -> String {
        isTurkish ? turkish : english
    }
}
