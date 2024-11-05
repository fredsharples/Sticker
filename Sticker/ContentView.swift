import SwiftUI

struct ContentView: View {
    @StateObject private var arViewModel = ARViewModel()
    
    var body: some View {
        TabView {
            NavigationStack {
                PickerView(arViewModel: arViewModel)
            }
            .tabItem {
                Label("View", systemImage: "binoculars")
            }
            .padding(.bottom, 8) // Add padding to make tab items taller
            
            DiscoverView()
            .tabItem {
                Label("Discover", systemImage: "map")
            }
            .padding(.bottom, 8) // Add padding to make tab items taller
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
