import SwiftUI
import AVFoundation

// MARK: - Main Scanner View

struct ScannerView: View {
    @StateObject private var viewModel = ScannerViewModel()
    @State private var selectedCard: Card? = nil
    @State private var showGamePicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                // Camera preview
                if let session = viewModel.captureSession {
                    CameraPreviewView(session: session)
                        .ignoresSafeArea()
                }

                // Scanner overlay
                ScannerOverlayView(state: viewModel.state, selectedGame: viewModel.selectedGame)

                // Bottom controls
                VStack {
                    Spacer()
                    bottomControls
                }
            }
            .navigationTitle("Scan Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    gamePickerButton
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    flashButton
                }
            }
            .sheet(isPresented: Binding(
                get: { showGamePicker },
                set: { showGamePicker = $0 }
            )) {
                GamePickerSheet(selectedGame: $viewModel.selectedGame)
            }
            .navigationDestination(item: $selectedCard) { card in
                CardDetailView(card: card)
            }
            .task {
                await viewModel.setupCamera()
            }
            .onDisappear {
                viewModel.stopCamera()
            }
            .onChange(of: viewModel.state) { _, newState in
                if case .results(let cards) = newState, let first = cards.first {
                    selectedCard = first
                }
            }
        }
    }

    // MARK: - Subviews

    private var gamePickerButton: some View {
        Button {
            showGamePicker = true
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.selectedGame.icon)
                Text(viewModel.selectedGame.rawValue)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var flashButton: some View {
        Button {
            viewModel.toggleFlash()
        } label: {
            Image(systemName: viewModel.isFlashOn ? "bolt.fill" : "bolt.slash")
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        VStack(spacing: 12) {
            switch viewModel.state {
            case .scanning:
                Text("Point camera at a TCG card")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal)

            case .detected(let name):
                VStack(spacing: 8) {
                    Text("Detected: \(name)")
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        Button("Search Prices") {
                            viewModel.searchDetectedCard()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                        Button("Dismiss") {
                            viewModel.resetToScanning()
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                }

            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("Searching CardMarket…")
                        .foregroundColor(.white)
                }

            case .results(let cards):
                Text("Found \(cards.count) result\(cards.count == 1 ? "" : "s")")
                    .foregroundColor(.green)
                    .font(.subheadline)

            case .error(let message):
                VStack(spacing: 8) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Try Again") {
                        viewModel.dismissError()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }

            case .permissionDenied:
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                        .foregroundColor(.yellow)
                    Text("Camera access denied.\nEnable it in Settings → Privacy → Camera.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .font(.subheadline)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

            case .cameraUnavailable:
                Text("Camera not available on this device.")
                    .foregroundColor(.white)

            case .idle:
                EmptyView()
            }
        }
        .padding()
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}

// MARK: - Scanner Overlay

struct ScannerOverlayView: View {
    let state: ScannerState
    let selectedGame: TCGGame

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dimmed surround
                Color.black.opacity(0.4)
                    .mask(
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .frame(width: scanFrame(geo).width, height: scanFrame(geo).height)
                                    .blendMode(.destinationOut)
                            )
                    )

                // Scan frame border
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 3)
                    .frame(width: scanFrame(geo).width, height: scanFrame(geo).height)
                    .animation(.easeInOut(duration: 0.3), value: state)

                // Corner markers
                CornerMarkersView(size: scanFrame(geo))
                    .foregroundColor(selectedGame.accentColor)
            }
        }
    }

    private func scanFrame(_ geo: GeometryProxy) -> CGSize {
        CGSize(width: geo.size.width * 0.85, height: geo.size.width * 0.85 * 0.7)
    }

    private var borderColor: Color {
        switch state {
        case .detected:  return .green
        case .loading:   return .yellow
        case .error:     return .red
        default:         return .white.opacity(0.8)
        }
    }
}

struct CornerMarkersView: View {
    let size: CGSize
    let length: CGFloat = 20
    let thickness: CGFloat = 3

    var body: some View {
        ZStack {
            // Top-left
            cornerMark(rotation: 0)
                .offset(x: -size.width / 2 + length / 2, y: -size.height / 2 + length / 2)
            // Top-right
            cornerMark(rotation: 90)
                .offset(x: size.width / 2 - length / 2, y: -size.height / 2 + length / 2)
            // Bottom-left
            cornerMark(rotation: 270)
                .offset(x: -size.width / 2 + length / 2, y: size.height / 2 - length / 2)
            // Bottom-right
            cornerMark(rotation: 180)
                .offset(x: size.width / 2 - length / 2, y: size.height / 2 - length / 2)
        }
    }

    private func cornerMark(rotation: Double) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: length))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: length, y: 0))
        }
        .stroke(style: StrokeStyle(lineWidth: thickness, lineCap: .round))
        .frame(width: length, height: length)
        .rotationEffect(.degrees(rotation))
    }
}

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        var session: AVCaptureSession? {
            didSet { previewLayer.session = session }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = bounds
        }
    }
}

// MARK: - Game Picker Sheet

struct GamePickerSheet: View {
    @Binding var selectedGame: TCGGame
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(TCGGame.allCases) { game in
                Button {
                    selectedGame = game
                    dismiss()
                } label: {
                    HStack {
                        Text(game.icon)
                            .font(.title2)
                        Text(game.rawValue)
                            .foregroundColor(.primary)
                        Spacer()
                        if selectedGame == game {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Select Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
