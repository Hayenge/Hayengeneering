import Foundation
import CryptoKit

// MARK: - Configuration

struct CardMarketConfig {
    /// CardMarket API v2.0 base URL
    static let baseURL = "https://api.cardmarket.com/ws/v2.0/output.json"

    // TODO: Replace with your CardMarket API credentials from:
    // https://www.cardmarket.com/en/Magic/Account/API
    static var appToken = "YOUR_APP_TOKEN"
    static var appSecret = "YOUR_APP_SECRET"
    static var accessToken = "YOUR_ACCESS_TOKEN"
    static var accessTokenSecret = "YOUR_ACCESS_TOKEN_SECRET"

    static var isConfigured: Bool {
        !appToken.hasPrefix("YOUR_")
    }
}

// MARK: - CardMarket Service

final class CardMarketService {
    static let shared = CardMarketService()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Search for cards by name and game
    func searchCards(name: String, game: TCGGame, maxResults: Int = 30) async throws -> [Card] {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw CardMarketError.invalidQuery
        }

        let endpoint = "\(CardMarketConfig.baseURL)/products/find"
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "search", value: name),
            URLQueryItem(name: "idGame", value: String(game.cardMarketGameId)),
            URLQueryItem(name: "idLanguage", value: "1"),   // 1 = English
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]

        guard let url = components.url else { throw CardMarketError.invalidURL }

        let request = try buildRequest(url: url, method: "GET")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let searchResponse = try JSONDecoder().decode(CardSearchResponse.self, from: data)
        let products = searchResponse.products ?? (searchResponse.product.map { [$0] } ?? [])
        return products.map { $0.toCard(game: game) }
    }

    /// Get price guide for a specific product
    func getPriceGuide(productId: Int) async throws -> PriceGuide {
        let endpoint = "\(CardMarketConfig.baseURL)/products/\(productId)"
        guard let url = URL(string: endpoint) else { throw CardMarketError.invalidURL }

        let request = try buildRequest(url: url, method: "GET")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        struct ProductResponse: Decodable {
            let product: ProductDetail
            struct ProductDetail: Decodable {
                let priceGuide: PriceGuide
            }
        }

        let decoded = try JSONDecoder().decode(ProductResponse.self, from: data)
        return decoded.product.priceGuide
    }

    /// Get marketplace listings (articles) for a product
    func getArticles(productId: Int, maxResults: Int = 50) async throws -> [CardArticle] {
        let endpoint = "\(CardMarketConfig.baseURL)/articles/\(productId)"
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "start", value: "0"),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]

        guard let url = components.url else { throw CardMarketError.invalidURL }

        let request = try buildRequest(url: url, method: "GET")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let articlesResponse = try JSONDecoder().decode(ArticlesResponse.self, from: data)
        return articlesResponse.article.articles
    }

    // MARK: - OAuth 1.0a

    private func buildRequest(url: URL, method: String) throws -> URLRequest {
        guard CardMarketConfig.isConfigured else {
            throw CardMarketError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        let authHeader = buildOAuthHeader(url: url, method: method)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        return request
    }

    private func buildOAuthHeader(url: URL, method: String) -> String {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")

        let oauthParams: [(String, String)] = [
            ("oauth_consumer_key",     CardMarketConfig.appToken),
            ("oauth_nonce",            nonce),
            ("oauth_signature_method", "HMAC-SHA1"),
            ("oauth_timestamp",        timestamp),
            ("oauth_token",            CardMarketConfig.accessToken),
            ("oauth_version",          "1.0")
        ]

        let signature = buildSignature(
            method: method,
            url: url,
            oauthParams: oauthParams
        )

        var allParams = oauthParams
        allParams.append(("oauth_signature", signature))

        let headerValue = allParams
            .sorted { $0.0 < $1.0 }
            .map { "\(percentEncode($0.0))=\"\(percentEncode($0.1))\"" }
            .joined(separator: ", ")

        return "OAuth realm=\"\(url.absoluteString)\", \(headerValue)"
    }

    private func buildSignature(method: String, url: URL, oauthParams: [(String, String)]) -> String {
        // Collect all parameters (OAuth + query string)
        var allParams = oauthParams
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                allParams.append((item.name, item.value ?? ""))
            }
        }

        // Sort parameters and build parameter string
        let paramString = allParams
            .sorted { $0.0 < $1.0 }
            .map { "\(percentEncode($0.0))=\(percentEncode($0.1))" }
            .joined(separator: "&")

        // Build base URL (scheme + host + path, no query string)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.query = nil
        let baseURL = components.url!.absoluteString

        // Signature base string
        let baseString = [
            method.uppercased(),
            percentEncode(baseURL),
            percentEncode(paramString)
        ].joined(separator: "&")

        // Signing key
        let signingKey = "\(percentEncode(CardMarketConfig.appSecret))&\(percentEncode(CardMarketConfig.accessTokenSecret))"

        return hmacSHA1(key: signingKey, message: baseString)
    }

    private func hmacSHA1(key: String, message: String) -> String {
        let keyData = Data(key.utf8)
        let messageData = Data(message.utf8)
        let symmetricKey = SymmetricKey(data: keyData)
        let signature = HMAC<Insecure.SHA1>.authenticationCode(for: messageData, using: symmetricKey)
        return Data(signature).base64EncodedString()
    }

    private func percentEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    // MARK: - Response Validation

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CardMarketError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw CardMarketError.unauthorized
        case 404:
            throw CardMarketError.notFound
        case 429:
            throw CardMarketError.rateLimited
        default:
            throw CardMarketError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Errors

enum CardMarketError: LocalizedError {
    case notConfigured
    case invalidQuery
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case rateLimited
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "CardMarket API credentials not configured. Add your credentials in CardMarketConfig."
        case .invalidQuery:
            return "Please enter a card name to search."
        case .invalidURL:
            return "Invalid request URL."
        case .invalidResponse:
            return "Invalid server response."
        case .unauthorized:
            return "Invalid CardMarket API credentials. Check your App Token and Secret."
        case .notFound:
            return "Card not found on CardMarket."
        case .rateLimited:
            return "Too many requests. Please wait before searching again."
        case .httpError(let code):
            return "Server error (HTTP \(code))."
        }
    }
}
