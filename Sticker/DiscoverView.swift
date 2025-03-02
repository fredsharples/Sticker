import SwiftUI
import MapKit
import CoreLocation

// Custom annotation for sticker clusters
class StickerClusterAnnotation: NSObject, MKAnnotation, Identifiable {
    let coordinate: CLLocationCoordinate2D
    let stickerCount: Int
    let id = UUID()
    
    init(coordinate: CLLocationCoordinate2D, stickerCount: Int) {
        self.coordinate = coordinate
        self.stickerCount = stickerCount
        super.init()
    }
}

// Helper struct for grouping locations
private struct LocationGroup {
    var coordinate: CLLocationCoordinate2D
    var count: Int
}

struct DiscoverView: View {
    // Moved to above with other state variables
    @State private var annotations: [StickerClusterAnnotation] = []
    @State private var searchText = ""
    @State private var userMovedMap = false
    // Start with a reasonable default region (San Francisco), but we'll update it with user's location ASAP
    @StateObject private var locationManager = ARLocationManager()
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var hasSetInitialLocation = false
    private let firebaseManager = FirebaseManager()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Create a custom map binding with gesture detection
                Map(coordinateRegion: Binding(
                    get: { mapRegion },
                    set: { newRegion in
                        // If the region changed, flag it as a user interaction
                        if abs(newRegion.center.latitude - mapRegion.center.latitude) > 0.0001 ||
                           abs(newRegion.center.longitude - mapRegion.center.longitude) > 0.0001 ||
                           abs(newRegion.span.latitudeDelta - mapRegion.span.latitudeDelta) > 0.001 ||
                           abs(newRegion.span.longitudeDelta - mapRegion.span.longitudeDelta) > 0.001 {
                            // Small threshold to avoid false positives from tiny precision changes
                            userMovedMap = true
                        }
                        mapRegion = newRegion
                    }
                ),
                showsUserLocation: true,
                annotationItems: annotations) { annotation in
                    MapAnnotation(coordinate: annotation.coordinate) {
                        ZStack {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 40, height: 40)
                            
                            Text(annotation.stickerCount > 999 ? "999+" : "\(annotation.stickerCount)")
                                .foregroundColor(.white)
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                }
                
                // Show loading indicator if location hasn't been set yet
                if !hasSetInitialLocation {
                    ProgressView("Locating...")
                        .padding()
                        .background(Color(.systemBackground).opacity(0.8))
                        .cornerRadius(10)
                }
                
                VStack {
                    Spacer()
                    HStack {
                        Button(action: {
                            centerUserLocation()
                            loadStickers()
                        }) {
                            Image(systemName: "location.fill")
                                .padding()
                                .background(Color.white)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 32)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Discover Stickers")
            .searchable(text: $searchText, prompt: "Search for a location")
            .onSubmit(of: .search) {
                searchLocation()
            }
            .onAppear {
                print("DiscoverView appeared")
                initializeMapToUserLocation()
                loadStickers()
            }
        }
    }
    
    private func initializeMapToUserLocation() {
        // Check if we already have a location from the manager
        if let location = locationManager.location {
            print("Using existing location for map initialization: \(location.coordinate)")
            DispatchQueue.main.async {
                self.mapRegion = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                )
                self.hasSetInitialLocation = true
            }
        }
        
        // Set up callback for initial location determination or updates
        locationManager.onFirstLocationUpdate = { location in
            // Only update if we haven't set the location yet or the user hasn't moved the map
            if !self.hasSetInitialLocation && !self.userMovedMap {
                print("Received location update: \(location.coordinate)")
                
                DispatchQueue.main.async {
                    self.mapRegion = MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                    )
                    self.hasSetInitialLocation = true
                }
            }
        }
    }
    
    private func loadStickers() {
        firebaseManager.loadAnchors { result in
            switch result {
            case .success(let anchors):
                var groups: [LocationGroup] = []
                
                // Process each anchor
                for anchor in anchors {
                    let coord = CLLocationCoordinate2D(
                        latitude: anchor.latitude,
                        longitude: anchor.longitude
                    )
                    let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    
                    // Try to find a nearby group
                    if let index = groups.firstIndex(where: { group in
                        let groupLocation = CLLocation(
                            latitude: group.coordinate.latitude,
                            longitude: group.coordinate.longitude
                        )
                        return location.distance(from: groupLocation) <= ARConstants.discoveryRange
                    }) {
                        // Update existing group
                        groups[index].count += 1
                    } else {
                        // Create new group
                        groups.append(LocationGroup(coordinate: coord, count: 1))
                    }
                }
                
                // Convert groups to annotations
                annotations = groups.map { group in
                    StickerClusterAnnotation(
                        coordinate: group.coordinate,
                        stickerCount: group.count
                    )
                }
                
            case .failure(let error):
                print("Failed to load stickers: \(error)")
            }
        }
    }
    
    private func centerUserLocation() {
        if let location = locationManager.location {
            userMovedMap = false  // Reset this flag when user explicitly centers the map
            mapRegion = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
    }
    
    private func searchLocation() {
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = searchText
        
        let search = MKLocalSearch(request: searchRequest)
        search.start { response, _ in
            guard let response = response else { return }
            
            if let firstItem = response.mapItems.first {
                userMovedMap = true  // Set this flag since the map is being moved programmatically by search
                mapRegion = MKCoordinateRegion(
                    center: firstItem.placemark.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                )
            }
        }
    }
}
