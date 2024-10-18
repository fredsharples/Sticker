import SwiftUI
import MapKit
import CoreLocation

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

struct DiscoverView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var annotations: [StickerAnnotation] = []
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                Map(coordinateRegion: $locationManager.region, showsUserLocation: true, annotationItems: annotations) { annotation in
                    MapAnnotation(coordinate: annotation.coordinate) {
                        Image(systemName: "star.circle.fill")
                            .foregroundColor(.red)
                            .frame(width: 44, height: 44)
                    }
                }
                .gesture(DragGesture()
                    .onEnded { _ in
                        let newAnnotation = StickerAnnotation(coordinate: locationManager.region.center)
                        annotations.append(newAnnotation)
                    }
                )
                
                VStack {
                    Spacer()
                    HStack {
                        Button(action: centerUserLocation) {
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

struct StickerAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct DiscoverView_Previews: PreviewProvider {
    static var previews: some View {
        DiscoverView()
    }
}
