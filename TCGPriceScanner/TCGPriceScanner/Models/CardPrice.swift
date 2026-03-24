import Foundation

// MARK: - Price Guide (summary prices from CardMarket)

struct PriceGuide: Codable, Hashable {
    /// Lowest price among all listings
    let low: Double?
    /// Average (mid) price
    let mid: Double?
    /// High price
    let high: Double?
    /// 30-day price trend
    let trend: Double?
    /// Average sell price (avg1: last day)
    let averageSellPrice: Double?
    /// Average sell price last 7 days
    let avg7: Double?
    /// Average sell price last 30 days
    let avg30: Double?
    /// Low foil price
    let lowFoil: Double?
    /// Trend foil price
    let trendFoil: Double?

    enum CodingKeys: String, CodingKey {
        case low = "LOW"
        case mid = "MID"
        case high = "HIGH"
        case trend = "TREND"
        case averageSellPrice = "AVG"
        case avg7 = "AVG7"
        case avg30 = "AVG30"
        case lowFoil = "LOWFOIL"
        case trendFoil = "TRENDFOIL"
    }
}

// MARK: - Individual Article (marketplace listing)

struct CardArticle: Identifiable, Decodable {
    let id: Int
    let seller: Seller
    let price: Double
    let condition: CardCondition
    let count: Int
    let isFoil: Bool
    let isPlayset: Bool
    let isAltered: Bool
    let isSigned: Bool
    let language: String?
    let comments: String?

    enum CodingKeys: String, CodingKey {
        case id = "idArticle"
        case seller
        case price
        case condition
        case count
        case isFoil
        case isPlayset
        case isAltered
        case isSigned
        case language
        case comments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        seller = try container.decode(Seller.self, forKey: .seller)
        price = try container.decode(Double.self, forKey: .price)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
        isFoil = try container.decodeIfPresent(Bool.self, forKey: .isFoil) ?? false
        isPlayset = try container.decodeIfPresent(Bool.self, forKey: .isPlayset) ?? false
        isAltered = try container.decodeIfPresent(Bool.self, forKey: .isAltered) ?? false
        isSigned = try container.decodeIfPresent(Bool.self, forKey: .isSigned) ?? false
        language = try container.decodeIfPresent(String.self, forKey: .language)
        comments = try container.decodeIfPresent(String.self, forKey: .comments)

        let conditionString = try container.decodeIfPresent(String.self, forKey: .condition) ?? "PO"
        condition = CardCondition(rawValue: conditionString) ?? .poorlyPlayed
    }

    struct Seller: Decodable {
        let username: String
        let idUser: Int?
        let country: String?
        let avgRating: Double?
        let numRatings: Int?
    }
}

// MARK: - Card Condition

enum CardCondition: String, CaseIterable, Decodable {
    case mintMint = "MM"
    case nearMint = "NM"
    case excellentMinus = "EX"
    case goodPlus = "GD"
    case good = "LP"
    case poorlyPlayed = "PL"
    case poor = "PO"

    var displayName: String {
        switch self {
        case .mintMint:      return "Mint"
        case .nearMint:      return "Near Mint"
        case .excellentMinus: return "Excellent"
        case .goodPlus:      return "Good+"
        case .good:          return "Good"
        case .poorlyPlayed:  return "Lightly Played"
        case .poor:          return "Poor"
        }
    }

    var shortName: String { rawValue }
}

// MARK: - Articles response wrapper

struct ArticlesResponse: Decodable {
    let article: ArticleContainer

    enum ArticleContainer: Decodable {
        case array([CardArticle])
        case single(CardArticle)

        var articles: [CardArticle] {
            switch self {
            case .array(let arr): return arr
            case .single(let a): return [a]
            }
        }

        init(from decoder: Decoder) throws {
            if let array = try? decoder.singleValueContainer().decode([CardArticle].self) {
                self = .array(array)
            } else if let single = try? decoder.singleValueContainer().decode(CardArticle.self) {
                self = .single(single)
            } else {
                self = .array([])
            }
        }
    }
}

// MARK: - Scan history entry

struct ScanHistoryEntry: Identifiable, Codable {
    let id: UUID
    let card: Card
    let scannedAt: Date

    init(card: Card) {
        self.id = UUID()
        self.card = card
        self.scannedAt = Date()
    }
}

// MARK: - Formatting helpers

extension Double {
    func priceString(currency: String = "€") -> String {
        String(format: "\(currency) %.2f", self)
    }

    func usdString() -> String {
        String(format: "$%.2f", self)
    }
}
