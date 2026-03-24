import Foundation

// MARK: - Configuration

struct PriceChartingConfig {
    static let baseURL = "https://www.pricecharting.com/api"

    // TODO: Replace with your PriceCharting API key from:
    // https://www.pricecharting.com/api-documentation
    static var apiKey = "YOUR_API_KEY"

    static var isConfigured: Bool {
        !apiKey.hasPrefix("YOUR_")
    }
}

// MARK: - PriceCharting Service

final class PriceChartingService {
    static let shared = PriceChartingService()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Search for a card and return its price data.
    /// Returns nil if no match is found.
    func searchPrice(name: String, consoleName: String) async throws -> PriceChartingPrice? {
        guard PriceChartingConfig.isConfigured else {
            throw PriceChartingError.notConfigured
        }

        // Step 1: Search for products matching the name
        let products = try await searchProducts(name: name, consoleName: consoleName)
        guard let product = products.first else { return nil }

        // Step 2: Fetch full price detail for the product
        return try await fetchProductDetail(id: product.id)
    }

    // MARK: - Search Products

    private func searchProducts(name: String, consoleName: String) async throws -> [PriceChartingProduct] {
        var components = URLComponents(string: "\(PriceChartingConfig.baseURL)/products")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "\(name) \(consoleName)"),
            URLQueryItem(name: "status", value: "price_lookup"),
            URLQueryItem(name: "id", value: consoleName)
        ]

        guard let url = components.url else { throw PriceChartingError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        // PriceCharting returns {"products": [...]} or just an array
        if let decoded = try? JSONDecoder().decode(PriceChartingSearchResponse.self, from: data) {
            return decoded.products.filter { matchesConsoleName($0.consoleName, target: consoleName) }
        }
        return []
    }

    // MARK: - Fetch Product Detail

    private func fetchProductDetail(id: String) async throws -> PriceChartingPrice? {
        var components = URLComponents(string: "\(PriceChartingConfig.baseURL)/product")!
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "api_key", value: PriceChartingConfig.apiKey)
        ]

        guard let url = components.url else { throw PriceChartingError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let detail = try JSONDecoder().decode(PriceChartingDetailResponse.self, from: data)

        let productURL = URL(string: "https://www.pricecharting.com/game/\(detail.consoleName ?? "")/\(id)")

        // PriceCharting returns prices in cents
        return PriceChartingPrice(
            id: detail.id,
            name: detail.name,
            consoleName: detail.consoleName,
            url: productURL,
            loosePrice: detail.loosePrice.map { Double($0) / 100.0 },
            gradedPrice: detail.gradedPrice.map { Double($0) / 100.0 },
            newPrice: detail.newPrice.map { Double($0) / 100.0 },
            completePrice: detail.completePrice.map { Double($0) / 100.0 }
        )
    }

    // MARK: - Helpers

    private func matchesConsoleName(_ consoleName: String?, target: String) -> Bool {
        guard let cn = consoleName?.lowercased() else { return false }
        let t = target.lowercased()
        return cn.contains(t) || t.contains(cn)
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw PriceChartingError.invalidResponse
        }
        switch http.statusCode {
        case 200...299: return
        case 401: throw PriceChartingError.unauthorized
        case 404: throw PriceChartingError.notFound
        case 429: throw PriceChartingError.rateLimited
        default:  throw PriceChartingError.httpError(http.statusCode)
        }
    }
}

// MARK: - Errors

enum PriceChartingError: LocalizedError {
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
            return "PriceCharting API key not configured. Add your key in PriceChartingConfig."
        case .invalidURL:   return "Invalid request URL."
        case .invalidResponse: return "Invalid server response."
        case .unauthorized: return "Invalid PriceCharting API key."
        case .notFound:     return "Card not found on PriceCharting."
        case .rateLimited:  return "Too many requests to PriceCharting. Please wait."
        case .httpError(let c): return "PriceCharting server error (HTTP \(c))."
        }
    }
}
