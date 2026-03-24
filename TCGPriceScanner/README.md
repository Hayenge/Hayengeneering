# TCG Price Scanner

An iOS app that scans Trading Card Game cards using your camera and shows live prices from [CardMarket](https://www.cardmarket.com).

## Supported Games

| Game | CardMarket ID |
|------|--------------|
| Magic: The Gathering | 1 |
| Yu-Gi-Oh! | 3 |
| Pokémon | 6 |
| Star Wars: Unlimited | 18 |
| One Piece | 19 |
| Disney Lorcana | 22 |
| Dragon Ball Super | 25 |
| Flesh and Blood | 40 |

## Features

- **Camera Scanner** — Point your phone at any TCG card. The app uses on-device OCR (Apple Vision framework) to read the card name and auto-detect the game.
- **Live CardMarket Prices** — Fetches the full price guide (Low / Mid / High / Trend / Avg7 / Avg30 / Foil) and live marketplace listings.
- **Manual Search** — Search by card name across any supported TCG.
- **Scan History** — Quickly revisit previously scanned cards and their prices.
- **Marketplace Listings** — Browse individual seller listings with condition, country, seller rating, foil/playset flags, and price.
- **Filters & Sorting** — Filter by card condition, foil-only toggle, and sort by price or seller rating.

## Requirements

- Xcode 15+
- iOS 16.0+ device (camera required for scanning)
- CardMarket developer account for live prices

## Setup

### 1. Generate the Xcode Project

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj` from `project.yml`.

```bash
# Install XcodeGen (requires Homebrew)
brew install xcodegen

# Generate the Xcode project
cd TCGPriceScanner
xcodegen generate
```

Then open `TCGPriceScanner.xcodeproj` in Xcode.

### 2. Configure CardMarket API Credentials

1. Log in to [CardMarket](https://www.cardmarket.com) and go to **Account → API** to create an app.
2. Copy your **App Token**, **App Secret**, **Access Token**, and **Access Token Secret**.
3. Open `TCGPriceScanner/Services/CardMarketService.swift` and fill in:

```swift
struct CardMarketConfig {
    static var appToken         = "YOUR_APP_TOKEN"
    static var appSecret        = "YOUR_APP_SECRET"
    static var accessToken      = "YOUR_ACCESS_TOKEN"
    static var accessTokenSecret = "YOUR_ACCESS_TOKEN_SECRET"
}
```

> Without credentials the app still works — it shows the price guide data returned in product search results, but live marketplace listings require valid credentials.

### 3. Set Your Development Team

In Xcode, select the `TCGPriceScanner` target → **Signing & Capabilities** → set your Apple Developer **Team**.

### 4. Build & Run

Select a physical iPhone (camera is required for scanning) and press **Run**.

## Architecture

```
TCGPriceScanner/
├── Models/
│   ├── TCGGame.swift          # Supported games + CardMarket game IDs
│   ├── Card.swift             # Card model + CardMarket API decoding
│   └── CardPrice.swift        # PriceGuide, CardArticle, ScanHistoryEntry
├── Services/
│   ├── CardMarketService.swift  # OAuth 1.0a + CardMarket API v2.0
│   └── CardRecognitionService.swift  # Vision OCR card name extraction
├── ViewModels/
│   ├── ScannerViewModel.swift    # Camera session + OCR + search
│   └── CardPriceViewModel.swift  # Price loading + filtering + sorting
└── Views/
    ├── ScannerView.swift        # Camera live preview + scan overlay
    ├── CardDetailView.swift     # Card info + price guide + listings
    ├── SearchView.swift         # Manual card search
    └── HistoryView.swift        # Scan history
```

## CardMarket API

Uses **CardMarket API v2.0** with **OAuth 1.0a** (HMAC-SHA1). Key endpoints:

| Endpoint | Description |
|----------|-------------|
| `GET /products/find?search={name}&idGame={id}` | Search products |
| `GET /products/{idProduct}` | Product details + price guide |
| `GET /articles/{idProduct}` | Marketplace listings |

## License

MIT
