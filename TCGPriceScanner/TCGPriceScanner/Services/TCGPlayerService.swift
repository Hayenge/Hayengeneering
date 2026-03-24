import Foundation

// MARK: - Configuration

struct TCGPlayerConfig {
    /// TCGPlayer API base URL
    static let baseURL = "https://api.tcgplayer.com"
    static let apiVersion = "v1.37.0"

    // TODO: Replace with your TCGPlayer API credentials from:
    // https://developer.tcgplayer.com/
    static var publicKey = "YOUR_PUBLIC_KEY"
    static var privateKey = "YOUR_PRIVATE_KEY"

    static var isConfigured: Bool {
        !publicKey.hasPrefix("YOUR_")
    }
}

// MARK: - Token Cache

private actor TCGPlayerTokenCache {
    var token: String?
    var expiry: Date = .distantPast

    var isValid: Bool {
        token != nil && Date() < expiry
    }

    func store(token: String, expiresIn: Int) {
        self.token = token
        // Subtract 60s buffer before expiry
        self.expiry = Date().addingTimeInterval(Double(expiresIn) - 60)
    }
}

// MARK: - TCGPlayer Service

final class TCGPlayerService {
    static let shared = TCGPlayerService()
    private let session: URLSession
    private let tokenCache = TCGPlayerTokenCache()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Search for a card by name and return its price data.
    /// Returns nil if the card is not found.
    func searchPrice(name: String, categoryId: Int) async throws -> TCGPlayerPrice? {
        guard TCGPlayerConfig.isConfigured else {
            throw TCGPlayerError.notConfigured
        }

        let token = try await fetchToken()

        // Step 1: Search for the product
        let products = try await searchProducts(name: name, categoryId: categoryId, token: token)
        guard let product = products.first else { return nil }

        // Step 2: Fetch pricing for the product
        let prices = try await fetchPricing(productId: product.productId, token: token)

        let normal = prices.first { $0.subTypeName == "Normal" || $0.subTypeName == nil }
        let foil   = prices.first { $0.subTypeName == "Foil" }

        let urlString = product.url.flatMap { URL(string: "https://www.tcgplayer.com\($0)") }

        return TCGPlayerPrice(
            productId: product.productId,
            productName: product.name,
            url: urlString,
            marketPrice: normal?.marketPrice,
            lowPrice: normal?.lowPrice,
            midPrice: normal?.midPrice,
            highPrice: normal?.highPrice,
            directLowPrice: normal?.directLowPrice,
            foilMarketPrice: foil?.marketPrice,
            foilLowPrice: foil?.lowPrice,
            foilMidPrice: foil?.midPrice,
            foilHighPrice: foil?.highPrice
        )
    }

    // MARK: - Token

    private func fetchToken() async throws -> String {
        if await tokenCache.isValid, let cached = await tokenCache.token {
            return cached
        }

        guard let url = URL(string: "\(TCGPlayerConfig.baseURL)/token") else {
            throw TCGPlayerError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=client_credentials&client_id=\(TCGPlayerConfig.publicKey)&client_secret=\(TCGPlayerConfig.privateKey)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let tokenResponse = try JSONDecoder().decode(TCGPlayerTokenResponse.self, from: data)
        await tokenCache.store(token: tokenResponse.accessToken, expiresIn: tokenResponse.expiresIn)
        return tokenResponse.accessToken
    }

    // MARK: - Search Products

    private func searchProducts(name: String, categoryId: Int, token: String) async throws -> [TCGPlayerProduct] {
        var components = URLComponents(string: "\(TCGPlayerConfig.baseURL)/\(TCGPlayerConfig.apiVersion)/catalog/products")!
        components.queryItems = [
            URLQueryItem(name: "productName", value: name),
            URLQueryItem(name: "categoryId", value: String(categoryId)),
            URLQueryItem(name: "productTypes", value: "Cards"),
            URLQueryItem(name: "getExtendedFields", value: "false"),
            URLQueryItem(name: "includeSkus", value: "false"),
            URLQueryItem(name: "limit", value: "5")
        ]

        guard let url = components.url else { throw TCGPlayerError.invalidURL }
        let request = buildRequest(url: url, token: token)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoded = try JSONDecoder().decode(TCGPlayerSearchResponse.self, from: data)
        return decoded.results
    }

    // MARK: - Fetch Pricing

    private func fetchPricing(productId: Int, token: String) async throws -> [TCGPlayerPricingResult] {
        guard let url = URL(string: "\(TCGPlayerConfig.baseURL)/\(TCGPlayerConfig.apiVersion)/pricing/product/\(productId)") else {
            throw TCGPlayerError.invalidURL
        }

        let request = buildRequest(url: url, token: token)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoded = try JSONDecoder().decode(TCGPlayerPricingResponse.self, from: data)
        return decoded.results
    }

    // MARK: - Helpers

    private func buildRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw TCGPlayerError.invalidResponse
        }
        switch http.statusCode {
        case 200...299: return
        case 401: throw TCGPlayerError.unauthorized
        case 404: throw TCGPlayerError.notFound
        case 429: throw TCGPlayerError.rateLimited
        default:  throw TCGPlayerError.httpError(http.statusCode)
        }
    }
}

// MARK: - Errors

enum TCGPlayerError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case rateLimited
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "TCGPlayer API credentials not configured. Add your Public/Private keys in TCGPlayerConfig."
        case .invalidURL:   return "Invalid request URL."
        case .invalidResponse: return "Invalid server response."
        case .unauthorized: return "Invalid TCGPlayer API credentials."
        case .notFound:     return "Card not found on TCGPlayer."
        case .rateLimited:  return "Too many requests to TCGPlayer. Please wait."
        case .httpError(let c): return "TCGPlayer server error (HTTP \(c))."
        }
    }
}
