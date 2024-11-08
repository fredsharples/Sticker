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
    @StateObject private var locationManager = LocationManager()
    @State private var annotations: [StickerClusterAnnotation] = []
    @State private var searchText = ""
    private let firebaseManager = FirebaseManager()
    
    var body: some View {
        NavigationView {
            ZStack {
                Map(coordinateRegion: $locationManager.region,
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
                        .padding()
                        
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
                loadStickers()
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
                        return location.distance(from: groupLocation) <= 50 // 50-meter radius
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
            locationManager.region = MKCoordinateRegion(
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
                locationManager.region = MKCoordinateRegion(
                    center: firstItem.placemark.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                )
            }
        }
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location
        region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    }
}
