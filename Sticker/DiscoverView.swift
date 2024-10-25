import SwiftUI
import MapKit
import CoreLocation

struct StickerCluster: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let stickers: [StickerAnnotation]
    
    var count: Int { stickers.count }
    var radius: Double {
        min(max(30.0, Double(count) * 10.0), 100.0)
    }
    
    var color: Color {
        switch count {
        case 1: return .blue.opacity(0.3)
        case 2...5: return .green.opacity(0.3)
        case 6...10: return .yellow.opacity(0.3)
        default: return .red.opacity(0.3)
        }
    }
}

struct StickerAnnotation: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let name: String
    let timestamp: Date
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

struct CircleOverlay: View {
    let cluster: StickerCluster
    
    var body: some View {
        ZStack {
            Circle()
                .fill(cluster.color)
                .frame(width: 60, height: 60)
            
            Text("\(cluster.count)")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .padding(8)
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
        }
    }
}

struct DiscoverView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var firebaseManager = FirebaseManager()
    @State private var annotations: [StickerAnnotation] = []
    @State private var clusters: [StickerCluster] = []
    @State private var searchText = ""
    @State private var selectedCluster: StickerCluster?
    
    var body: some View {
        NavigationView {
            ZStack {
                Map(coordinateRegion: $locationManager.region,
                    showsUserLocation: true,
                    annotationItems: clusters) { cluster in
                    MapAnnotation(coordinate: cluster.coordinate) {
                        CircleOverlay(cluster: cluster)
                            .onTapGesture {
                                selectedCluster = cluster
                            }
                    }
                }
                
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
                        
                        Button(action: refreshStickers) {
                            Image(systemName: "arrow.clockwise")
                                .padding()
                                .background(Color.white)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                        .padding()
                        
                        Spacer()
                    }
                }
                
                if firebaseManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                }
            }
            .navigationTitle("Discover Stickers")
            .searchable(text: $searchText, prompt: "Search for a location")
            .onSubmit(of: .search) {
                searchLocation()
            }
            .sheet(item: $selectedCluster) { cluster in
                ClusterDetailView(cluster: cluster)
            }
            .alert("Error", isPresented: Binding(
                get: { firebaseManager.error != nil },
                set: { if !$0 { firebaseManager.error = nil } }
            )) {
                Button("OK") { firebaseManager.error = nil }
            } message: {
                Text(firebaseManager.error?.localizedDescription ?? "Unknown error")
            }
        }
        .onAppear {
            refreshStickers()
        }
    }
    
    private func centerUserLocation() {
        if let location = locationManager.location {
            withAnimation {
                locationManager.region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            }
        }
    }
    
    private func refreshStickers() {
        guard let location = locationManager.location else { return }
        
        annotations.removeAll()
        clusters.removeAll()
        
        firebaseManager.fetchNearbyStickerData(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            radiusInKm: 1.0
        ) { stickerData in
            if let latitude = stickerData["latitude"] as? Double,
               let longitude = stickerData["longitude"] as? Double,
               let name = stickerData["name"] as? String,
               let id = stickerData["id"] as? String,
               let timestamp = stickerData["timestamp"] as? TimeInterval {
                
                let coordinate = CLLocationCoordinate2D(
                    latitude: latitude,
                    longitude: longitude
                )
                
                let annotation = StickerAnnotation(
                    id: id,
                    coordinate: coordinate,
                    name: name,
                    timestamp: Date(timeIntervalSince1970: timestamp)
                )
                
                DispatchQueue.main.async {
                    if !annotations.contains(where: { $0.id == id }) {
                        annotations.append(annotation)
                        updateClusters()
                    }
                }
            }
        }
    }
    
    private func updateClusters() {
        let clusterRadius: Double = 50 // meters
        var newClusters: [StickerCluster] = []
        var processedAnnotations = Set<String>()
        
        for annotation in annotations where !processedAnnotations.contains(annotation.id) {
            var clusterStickers: [StickerAnnotation] = [annotation]
            processedAnnotations.insert(annotation.id)
            
            for otherAnnotation in annotations where !processedAnnotations.contains(otherAnnotation.id) {
                let distance = CLLocation(latitude: annotation.coordinate.latitude,
                                       longitude: annotation.coordinate.longitude)
                    .distance(from: CLLocation(latitude: otherAnnotation.coordinate.latitude,
                                            longitude: otherAnnotation.coordinate.longitude))
                
                if distance <= clusterRadius {
                    clusterStickers.append(otherAnnotation)
                    processedAnnotations.insert(otherAnnotation.id)
                }
            }
            
            let centerLat = clusterStickers.map { $0.coordinate.latitude }.reduce(0.0, +) / Double(clusterStickers.count)
            let centerLon = clusterStickers.map { $0.coordinate.longitude }.reduce(0.0, +) / Double(clusterStickers.count)
            
            let cluster = StickerCluster(
                coordinate: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                stickers: clusterStickers
            )
            newClusters.append(cluster)
        }
        
        clusters = newClusters
    }
    
    private func searchLocation() {
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = searchText
        
        let search = MKLocalSearch(request: searchRequest)
        search.start { response, _ in
            guard let response = response else { return }
            
            if let firstItem = response.mapItems.first {
                withAnimation {
                    locationManager.region = MKCoordinateRegion(
                        center: firstItem.placemark.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                }
            }
        }
    }
}

struct ClusterDetailView: View {
    let cluster: StickerCluster
    
    var body: some View {
        NavigationView {
            List(cluster.stickers) { sticker in
                VStack(alignment: .leading) {
                    Text(sticker.name)
                        .font(.headline)
                    Text("Placed: \(sticker.formattedTime)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Cluster Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
