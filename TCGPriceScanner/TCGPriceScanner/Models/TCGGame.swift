import SwiftUI

enum TCGGame: String, CaseIterable, Identifiable, Codable {
    case magicTheGathering = "Magic: The Gathering"
    case pokemon = "Pokémon"
    case yugioh = "Yu-Gi-Oh!"
    case onePiece = "One Piece"
    case lorcana = "Disney Lorcana"
    case starWarsUnlimited = "Star Wars: Unlimited"
    case dragonBallSuper = "Dragon Ball Super"
    case flesh = "Flesh and Blood"

    var id: String { rawValue }

    /// CardMarket game identifier
    var cardMarketGameId: Int {
        switch self {
        case .magicTheGathering:    return 1
        case .yugioh:               return 3
        case .pokemon:              return 6
        case .onePiece:             return 19
        case .starWarsUnlimited:    return 18
        case .lorcana:              return 22
        case .dragonBallSuper:      return 25
        case .flesh:                return 40
        }
    }

    var icon: String {
        switch self {
        case .magicTheGathering:    return "🧙"
        case .pokemon:              return "⚡"
        case .yugioh:               return "🐉"
        case .onePiece:             return "☠️"
        case .lorcana:              return "✨"
        case .starWarsUnlimited:    return "⭐"
        case .dragonBallSuper:      return "🌟"
        case .flesh:                return "⚔️"
        }
    }

    var accentColor: Color {
        switch self {
        case .magicTheGathering:    return .brown
        case .pokemon:              return .yellow
        case .yugioh:               return .purple
        case .onePiece:             return .red
        case .lorcana:              return .blue
        case .starWarsUnlimited:    return .orange
        case .dragonBallSuper:      return .orange
        case .flesh:                return .red
        }
    }
}
