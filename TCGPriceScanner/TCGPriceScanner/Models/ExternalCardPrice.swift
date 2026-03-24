import Foundation

// MARK: - External Price Source State

enum ExternalPriceState {
    case idle
    case loading
    case loaded
    case notFound
    case notConfigured
    case unavailable   // Game not supported by this source
    case error(String)
}

// MARK: - TCGPlayer Price

struct TCGPlayerPrice {
    let productId: Int
    let productName: String
    let url: URL?

    // Normal prices (USD)
    let marketPrice: Double?
    let lowPrice: Double?
    let midPrice: Double?
    let highPrice: Double?
    let directLowPrice: Double?

    // Foil prices (USD)
    let foilMarketPrice: Double?
    let foilLowPrice: Double?
    let foilMidPrice: Double?
    let foilHighPrice: Double?
}

// MARK: - PriceCharting Price

struct PriceChartingPrice {
    let id: String
    let name: String
    let consoleName: String?
    let url: URL?

    // Prices in USD (PriceCharting returns cents; service converts to dollars)
    let loosePrice: Double?      // Ungraded / raw card
    let gradedPrice: Double?     // PSA/BGS graded
    let newPrice: Double?        // Sealed / pack-fresh
    let completePrice: Double?   // Complete-in-box (less relevant for TCG)
}

// MARK: - TCGPlayer API Response Models

struct TCGPlayerTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

struct TCGPlayerSearchResponse: Decodable {
    let results: [TCGPlayerProduct]
}

struct TCGPlayerProduct: Decodable {
    let productId: Int
    let name: String
    let url: String?

    enum CodingKeys: String, CodingKey {
        case productId
        case name
        case url
    }
}

struct TCGPlayerPricingResponse: Decodable {
    let results: [TCGPlayerPricingResult]
}

struct TCGPlayerPricingResult: Decodable {
    let productId: Int
    let subTypeName: String?
    let lowPrice: Double?
    let midPrice: Double?
    let highPrice: Double?
    let marketPrice: Double?
    let directLowPrice: Double?

    enum CodingKeys: String, CodingKey {
        case productId
        case subTypeName
        case lowPrice
        case midPrice
        case highPrice
        case marketPrice
        case directLowPrice
    }
}

// MARK: - PriceCharting API Response Models

struct PriceChartingSearchResponse: Decodable {
    let products: [PriceChartingProduct]

    enum CodingKeys: String, CodingKey {
        case products
    }
}

struct PriceChartingProduct: Decodable {
    let id: String
    let name: String
    let consoleName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name = "product-name"
        case consoleName = "console-name"
    }
}

struct PriceChartingDetailResponse: Decodable {
    let id: String
    let name: String
    let consoleName: String?
    // Prices are stored in cents as integers
    let loosePrice: Int?
    let gradedPrice: Int?
    let newPrice: Int?
    let completePrice: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name = "product-name"
        case consoleName = "console-name"
        case loosePrice = "loose-price"
        case gradedPrice = "graded-price"
        case newPrice = "new-price"
        case completePrice = "complete-price"
    }
}
