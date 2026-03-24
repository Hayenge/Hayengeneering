import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .scanner

    enum Tab {
        case scanner, search, history
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ScannerView()
                .tabItem {
                    Label("Scan", systemImage: "camera.viewfinder")
                }
                .tag(Tab.scanner)

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(Tab.search)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag(Tab.history)
        }
        .accentColor(.blue)
    }
}

#Preview {
    ContentView()
}
