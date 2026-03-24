import AVFoundation
import Combine
import SwiftUI
import Vision

// MARK: - Scanner State

enum ScannerState: Equatable {
    case idle
    case scanning
    case detected(String)           // card name found
    case loading
    case results([Card])
    case error(String)
    case cameraUnavailable
    case permissionDenied
}

// MARK: - Scanner ViewModel

@MainActor
final class ScannerViewModel: NSObject, ObservableObject {

    @Published var state: ScannerState = .idle
    @Published var selectedGame: TCGGame = .magicTheGathering
    @Published var captureSession: AVCaptureSession?
    @Published var scannedCards: [Card] = []
    @Published var isFlashOn: Bool = false
    @Published var detectedCardName: String = ""

    private let recognitionService = CardRecognitionService()
    private let apiService = CardMarketService.shared
    private var historyStore = ScanHistoryStore.shared

    private var videoOutput: AVCaptureVideoDataOutput?
    private var lastScanTime: Date = .distantPast
    private var scanThrottleInterval: TimeInterval = 1.5    // seconds between scans
    private var isProcessingFrame = false
    private let sessionQueue = DispatchQueue(label: "com.tcgpricescanner.camera", qos: .userInitiated)

    // MARK: - Camera Setup

    func setupCamera() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            await configureCaptureSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                await configureCaptureSession()
            } else {
                state = .permissionDenied
            }
        case .denied, .restricted:
            state = .permissionDenied
        @unknown default:
            state = .cameraUnavailable
        }
    }

    private func configureCaptureSession() async {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            state = .cameraUnavailable
            return
        }

        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        output.alwaysDiscardsLateVideoFrames = true

        guard session.canAddOutput(output) else {
            state = .cameraUnavailable
            return
        }

        session.addOutput(output)
        videoOutput = output
        captureSession = session

        sessionQueue.async { session.startRunning() }
        state = .scanning
    }

    func stopCamera() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }

    // MARK: - Flash

    func toggleFlash() {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            isFlashOn.toggle()
            device.torchMode = isFlashOn ? .on : .off
            device.unlockForConfiguration()
        } catch {}
    }

    // MARK: - Frame Processing

    func processPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        guard !isProcessingFrame,
              Date().timeIntervalSince(lastScanTime) >= scanThrottleInterval,
              case .scanning = state else { return }

        isProcessingFrame = true
        lastScanTime = Date()

        Task {
            defer { isProcessingFrame = false }

            guard let result = try? await recognitionService.recognise(pixelBuffer: pixelBuffer),
                  result.confidence > 0.6 else { return }

            let cardName = result.cardName
            guard !cardName.isEmpty else { return }

            await MainActor.run {
                detectedCardName = cardName
                if let detectedGame = result.detectedGame {
                    selectedGame = detectedGame
                }
                state = .detected(cardName)
            }
        }
    }

    // MARK: - Search

    func searchDetectedCard() {
        guard case .detected(let name) = state else { return }
        searchCard(name: name)
    }

    func searchCard(name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        state = .loading

        Task {
            do {
                let cards = try await apiService.searchCards(name: name, game: selectedGame)
                if cards.isEmpty {
                    state = .error("No cards found for \"\(name)\" in \(selectedGame.rawValue).")
                } else {
                    scannedCards = cards
                    state = .results(cards)
                    // Save top result to history
                    if let topCard = cards.first {
                        historyStore.add(topCard)
                    }
                }
            } catch CardMarketError.notConfigured {
                state = .error("Configure your CardMarket API credentials in CardMarketConfig.swift to see live prices.")
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func resetToScanning() {
        detectedCardName = ""
        state = .scanning
    }

    func dismissError() {
        state = .scanning
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ScannerViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { await processPixelBuffer(pixelBuffer) }
    }
}

// MARK: - Scan History Store

final class ScanHistoryStore: ObservableObject {
    static let shared = ScanHistoryStore()

    @Published private(set) var entries: [ScanHistoryEntry] = []

    private let storageKey = "scan_history"
    private let maxEntries = 100

    private init() {
        loadFromDisk()
    }

    func add(_ card: Card) {
        let entry = ScanHistoryEntry(card: card)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        saveToDisk()
    }

    func clear() {
        entries = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ScanHistoryEntry].self, from: data) else { return }
        entries = decoded
    }
}
