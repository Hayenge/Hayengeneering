import Foundation

struct Card: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let game: TCGGame
    let expansionName: String?
    let expansionId: Int?
    let imageURL: URL?
    let cardNumber: String?
    let rarity: String?
    let priceGuide: PriceGuide?
    let cardMarketURL: URL?

    // Maps to CardMarket API response
    enum CodingKeys: String, CodingKey {
        case id = "idProduct"
        case name
        case expansionName
        case expansionId = "idExpansion"
        case imageURL = "image"
        case cardNumber = "number"
        case rarity
        case priceGuide
        case cardMarketURL = "website"
        case game
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        game = try container.decodeIfPresent(TCGGame.self, forKey: .game) ?? .magicTheGathering
        priceGuide = try container.decodeIfPresent(PriceGuide.self, forKey: .priceGuide)
        cardNumber = try container.decodeIfPresent(String.self, forKey: .cardNumber)
        rarity = try container.decodeIfPresent(String.self, forKey: .rarity)

        // Expansion may be nested or flat
        expansionName = try container.decodeIfPresent(String.self, forKey: .expansionName)
        expansionId = try container.decodeIfPresent(Int.self, forKey: .expansionId)

        if let imageString = try container.decodeIfPresent(String.self, forKey: .imageURL) {
            imageURL = URL(string: "https://static.cardmarket.com\(imageString)")
        } else {
            imageURL = nil
        }

        if let urlString = try container.decodeIfPresent(String.self, forKey: .cardMarketURL) {
            cardMarketURL = URL(string: "https://www.cardmarket.com\(urlString)")
        } else {
            cardMarketURL = nil
        }
    }

    init(id: Int, name: String, game: TCGGame, expansionName: String? = nil,
         expansionId: Int? = nil, imageURL: URL? = nil, cardNumber: String? = nil,
         rarity: String? = nil, priceGuide: PriceGuide? = nil, cardMarketURL: URL? = nil) {
        self.id = id
        self.name = name
        self.game = game
        self.expansionName = expansionName
        self.expansionId = expansionId
        self.imageURL = imageURL
        self.cardNumber = cardNumber
        self.rarity = rarity
        self.priceGuide = priceGuide
        self.cardMarketURL = cardMarketURL
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(game, forKey: .game)
        try container.encodeIfPresent(expansionName, forKey: .expansionName)
        try container.encodeIfPresent(expansionId, forKey: .expansionId)
        try container.encodeIfPresent(cardNumber, forKey: .cardNumber)
        try container.encodeIfPresent(rarity, forKey: .rarity)
        try container.encodeIfPresent(priceGuide, forKey: .priceGuide)
    }
}

// MARK: - CardMarket API search response

struct CardSearchResponse: Decodable {
    let products: [CardProduct]?
    let product: CardProduct?

    enum CodingKeys: String, CodingKey {
        case products = "product"
        case product
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // CardMarket returns an array or single object depending on result count
        if let array = try? container.decode([CardProduct].self, forKey: .products) {
            products = array
            product = nil
        } else if let single = try? container.decode(CardProduct.self, forKey: .products) {
            products = [single]
            product = nil
        } else {
            products = nil
            product = try? container.decode(CardProduct.self, forKey: .product)
        }
    }
}

struct CardProduct: Decodable {
    let idProduct: Int
    let name: String
    let expansion: ExpansionInfo?
    let priceGuide: PriceGuide?
    let image: String?
    let website: String?
    let number: String?
    let rarity: String?

    struct ExpansionInfo: Decodable {
        let idExpansion: Int?
        let enName: String?
        let name: String?

        var displayName: String { enName ?? name ?? "Unknown Set" }
    }

    func toCard(game: TCGGame) -> Card {
        Card(
            id: idProduct,
            name: name,
            game: game,
            expansionName: expansion?.displayName,
            expansionId: expansion?.idExpansion,
            imageURL: image.flatMap { URL(string: "https://static.cardmarket.com\($0)") },
            cardNumber: number,
            rarity: rarity,
            priceGuide: priceGuide,
            cardMarketURL: website.flatMap { URL(string: "https://www.cardmarket.com\($0)") }
        )
    }
}
