import SwiftUI

struct ContentView: View {
    @StateObject private var arViewModel = ARViewModel()
    
    var body: some View {
        TabView {
            NavigationView {
                PickerView(arViewModel: arViewModel)
            }
            .tabItem {
                Label("Stickers", systemImage: "square.grid.3x3.fill")
            }
            
            DiscoverView()
            .tabItem {
                Label("Discover", systemImage: "map")
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
