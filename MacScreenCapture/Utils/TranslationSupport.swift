import Foundation
import NaturalLanguage

struct TranslationSupport {
    enum ParseError: Error {
        case emptyTranslation
        case invalidResponse
    }

    static func translatedTextFromGoogleResponse(_ data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              let translatedParts = root.first as? [Any] else {
            throw ParseError.invalidResponse
        }

        let translatedText = translatedParts.compactMap { item -> String? in
            guard let segment = item as? [Any] else { return nil }
            return segment.first as? String
        }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !translatedText.isEmpty else {
            throw ParseError.emptyTranslation
        }

        return translatedText
    }

    static func translatedTextFromMyMemoryResponse(_ data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseData = root["responseData"] as? [String: Any],
              let translatedText = responseData["translatedText"] as? String else {
            throw ParseError.invalidResponse
        }

        let trimmed = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ParseError.emptyTranslation
        }

        return trimmed
    }

    static func detectedLanguage(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else {
            return "en"
        }

        switch language {
        case .simplifiedChinese:
            return "zh-CN"
        case .traditionalChinese:
            return "zh-TW"
        case .english:
            return "en"
        case .japanese:
            return "ja"
        case .korean:
            return "ko"
        default:
            return language.rawValue
        }
    }

    static func myMemoryLanguageCode(for targetLanguage: String) -> String {
        switch targetLanguage {
        case "zh-CN":
            return "zh-CN"
        case "zh-TW":
            return "zh-TW"
        default:
            return targetLanguage
        }
    }

    static func appleLanguageCode(for language: String) -> String {
        switch language {
        case "zh-CN":
            return "zh-Hans"
        case "zh-TW":
            return "zh-Hant"
        default:
            return language
        }
    }

    static func displayName(forAppleLanguageCode language: String) -> String {
        switch appleLanguageCode(for: language) {
        case "zh-Hans":
            return "简体中文"
        case "zh-Hant":
            return "繁体中文"
        case "en":
            return "English"
        case "ja":
            return "日本語"
        case "ko":
            return "한국어"
        default:
            return language
        }
    }

    static func webTranslationURL(for text: String, targetLanguage: String) -> URL? {
        var components = URLComponents(string: "https://translate.google.com/")
        components?.queryItems = [
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: targetLanguage),
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "op", value: "translate")
        ]
        return components?.url
    }
}
