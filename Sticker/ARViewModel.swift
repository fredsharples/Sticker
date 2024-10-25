import SwiftUI
import RealityKit
import ARKit
import CoreLocation
import CoreMotion
import FirebaseAuth

class ARViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    // MARK: - Properties
    @Published var arView: ARView = ARView(frame: .zero)
    let firebaseManager = FirebaseManager()
    let locationManager = CLLocationManager()
    
    private var stickerEntities: [(entity: AnchorEntity, location: CLLocation)] = []
    
    @Published var currentLocation: CLLocation?
    @Published var selectedImageIndex: Int = 1
    @Published var isLoading = false
    @Published var error: Error?
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupARView()
        setupLocationManager()
        initializeFirebase()
    }
    
    // MARK: - Setup Methods
    /// Sets up AR view configuration and gesture recognizers
    private func setupARView() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        }
        arView.automaticallyConfigureSession = false
        arView.session.run(configuration)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
    }
    
    /// Sets up location manager
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    /// Initializes Firebase authentication
    private func initializeFirebase() {
        firebaseManager.loginFirebase { [weak self] result in
            switch result {
            case .success(let user):
                print("Logged in as user: \(user.uid)")
                self?.fetchNearbyStickerLocations() // Start fetching nearby stickers after login
            case .failure(let error):
                print("Failed to log in: \(error.localizedDescription)")
                self?.error = error
            }
        }
    }
    
    // MARK: - Location Delegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        
        // Fetch nearby stickers when location updates significantly
        if let lastLocation = locations.dropLast().last,
           location.distance(from: lastLocation) > 10 { // Only update if moved more than 10 meters
            fetchNearbyStickerLocations()
        }
    }
    
    // MARK: - Sticker Placement
    @objc private func handleTap(_ sender: UITapGestureRecognizer) {
        guard let currentLocation = currentLocation else { return }
        
        let location = sender.location(in: arView)
        let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
        
        if let firstResult = results.first {
            let anchorEntity = AnchorEntity(world: firstResult.worldTransform)
            anchorEntity.name = "placedObject"
            
            let imageName = String(format: "image_%04d", selectedImageIndex)
            let modelEntity = createModelEntity(img: imageName)
            
            // Orient the model upright
            modelEntity.setOrientation(simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]), relativeTo: nil)
            
            anchorEntity.addChild(modelEntity)
            arView.scene.addAnchor(anchorEntity)
            
            saveStickerToFirebase(anchorEntity: anchorEntity, location: currentLocation)
            stickerEntities.append((entity: anchorEntity, location: currentLocation))
        }
    }
    
    // MARK: - Sticker Management
    /// Fetches and displays nearby stickers
    private func fetchNearbyStickerLocations() {
        guard let userLocation = currentLocation else { return }
        
        isLoading = true
        firebaseManager.fetchNearbyStickerData(
            latitude: userLocation.coordinate.latitude,
            longitude: userLocation.coordinate.longitude,
            radiusInKm: 0.1 // 100 meters
        ) { [weak self] stickerData in
            guard let self = self else { return }
            self.isLoading = false
            
            if let latitude = stickerData["latitude"] as? Double,
               let longitude = stickerData["longitude"] as? Double,
               let transform = stickerData["transform"] as? [Double],
               let imageName = stickerData["name"] as? String,
               let id = stickerData["id"] as? String {
                
                // Check if we already have this sticker
                if !self.stickerEntities.contains(where: { $0.entity.id.description == id }) {
                    let stickerLocation = CLLocation(latitude: latitude, longitude: longitude)
                    let transformMatrix = self.arrayToTransform(transform)
                    
                    DispatchQueue.main.async {
                        let anchorEntity = AnchorEntity(world: transformMatrix)
                        let modelEntity = self.createModelEntity(img: imageName)
                        anchorEntity.addChild(modelEntity)
                        self.arView.scene.addAnchor(anchorEntity)
                        self.stickerEntities.append((entity: anchorEntity, location: stickerLocation))
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    /// Creates a model entity from an image
    private func createModelEntity(img: String) -> ModelEntity {
        let mesh = MeshResource.generatePlane(width: 0.2, depth: 0.2)
        guard let texture = try? TextureResource.load(named: img) else {
            print("Failed to load texture: \(img)")
            return ModelEntity()
        }
        
        var material = UnlitMaterial()
        material.baseColor = MaterialColorParameter.texture(texture)
        material.blending = .transparent(opacity: .init(floatLiteral: 1.0))
        
        let modelEntity = ModelEntity(mesh: mesh, materials: [material])
        if var model = modelEntity.model {
            model.materials = model.materials.map { material in
                var newMaterial = material as! UnlitMaterial
                newMaterial.blending = .transparent(opacity: .init(floatLiteral: 1.0))
                return newMaterial
            }
            modelEntity.model = model
        }
        
        return modelEntity
    }
    
    /// Saves sticker data to Firebase with correct transform data
    private func saveStickerToFirebase(anchorEntity: AnchorEntity, location: CLLocation) {
        let worldTransform = anchorEntity.transform.matrix
        let transformArray = transformToArray(worldTransform)
        let imageName = String(format: "image_%04d", selectedImageIndex)
        
        let stickerData: [String: Any] = [
            "id": anchorEntity.id.description,
            "transform": transformArray,
            "name": imageName,
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        print("Saving sticker: \(imageName) at location: \(location.coordinate)")
        
        firebaseManager.saveSticker(data: stickerData) { [weak self] result in
            if case .failure(let error) = result {
                self?.error = error
                print("Failed to save sticker: \(error.localizedDescription)")
            }
        }
    }
    
    /// Converts a 4x4 transformation matrix to an array
    private func transformToArray(_ transform: simd_float4x4) -> [Double] {
        return [
            Double(transform.columns.0.x), Double(transform.columns.0.y),
            Double(transform.columns.0.z), Double(transform.columns.0.w),
            Double(transform.columns.1.x), Double(transform.columns.1.y),
            Double(transform.columns.1.z), Double(transform.columns.1.w),
            Double(transform.columns.2.x), Double(transform.columns.2.y),
            Double(transform.columns.2.z), Double(transform.columns.2.w),
            Double(transform.columns.3.x), Double(transform.columns.3.y),
            Double(transform.columns.3.z), Double(transform.columns.3.w)
        ]
    }
    
    /// Converts an array back to a transformation matrix
    // Add these helper extensions to the class
       private func arrayToTransform(_ array: [Double]) -> simd_float4x4 {
           return simd_float4x4(rows: [
               SIMD4<Float>(Float(array[0]), Float(array[1]), Float(array[2]), Float(array[3])),
               SIMD4<Float>(Float(array[4]), Float(array[5]), Float(array[6]), Float(array[7])),
               SIMD4<Float>(Float(array[8]), Float(array[9]), Float(array[10]), Float(array[11])),
               SIMD4<Float>(Float(array[12]), Float(array[13]), Float(array[14]), Float(array[15]))
           ])
       }
    
    // MARK: - Public Methods
    /// Gets the distance to the nearest sticker
    func getDistanceToNearestSticker() -> Double? {
        guard let userLocation = currentLocation else { return nil }
        return stickerEntities.map { _, location in
            location.distance(from: userLocation)
        }.min()
    }
    
    /// Sets the selected sticker image
    func setSelectedImage(imageIndex: Int) {
        selectedImageIndex = imageIndex
        print("Selected sticker number: \(imageIndex)")
    }
    
    /// Clears all stickers from the AR scene
    func clearAll() {
        arView.scene.anchors.removeAll()
        stickerEntities.removeAll()
    }
    
    /// Deletes all stickers from Firebase
    func deleteAllfromFirebase() {
        firebaseManager.deleteAllAnchors { [weak self] result in
            if case .failure(let error) = result {
                self?.error = error
                print("Failed to delete anchors: \(error.localizedDescription)")
            }
        }
    }
    
    /// Loads stickers within specified radius of current location
    func loadNearbyStickers() {
        guard let currentLocation = currentLocation else {
            error = NSError(domain: "ARViewModel",
                           code: -1,
                           userInfo: [NSLocalizedDescriptionKey: "Current location not available"])
            return
        }
        
        isLoading = true
        
        // Clear existing stickers
        clearAll()
        
        // Make sure we have a valid AR session with world tracking
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        firebaseManager.fetchNearbyStickerData(
            latitude: currentLocation.coordinate.latitude,
            longitude: currentLocation.coordinate.longitude,
            radiusInKm: 0.006  // 6 meters
        ) { [weak self] stickerData in
            guard let self = self else { return }
            
            if let latitude = stickerData["latitude"] as? Double,
               let longitude = stickerData["longitude"] as? Double,
               let transform = stickerData["transform"] as? [Double],
               let imageName = stickerData["name"] as? String,
               let id = stickerData["id"] as? String {
                
                let stickerLocation = CLLocation(latitude: latitude, longitude: longitude)
                let distance = stickerLocation.distance(from: currentLocation)
                
                if distance <= 6 {
                    // Get center of the AR view
                    let center = CGPoint(x: self.arView.bounds.midX, y: self.arView.bounds.midY)
                    
                    // Perform raycast from center of screen
                    let results = self.arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any)
                    
                    // Convert the saved transform array to matrix
                    let transformMatrix = self.arrayToTransform(transform)
                    
                    if let firstResult = results.first {
                        // Create anchor entity at the raycast hit position
                        let anchorEntity = AnchorEntity(world: firstResult.worldTransform)
                        anchorEntity.name = id
                        
                        // Create the model entity
                        let modelEntity = self.createModelEntity(img: imageName)
                        
                        // Set the orientation
                        modelEntity.setOrientation(simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]), relativeTo: nil)
                        
                        anchorEntity.addChild(modelEntity)
                        
                        DispatchQueue.main.async {
                            self.arView.scene.addAnchor(anchorEntity)
                            self.stickerEntities.append((entity: anchorEntity, location: stickerLocation))
                            print("Loaded sticker: \(imageName) at distance: \(Int(distance))m")
                        }
                    } else {
                        // If no surface found, create a world anchor at the saved position
                        let anchorEntity = AnchorEntity(world: transformMatrix)
                        anchorEntity.name = id
                        let modelEntity = self.createModelEntity(img: imageName)
                        modelEntity.setOrientation(simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]), relativeTo: nil)
                        anchorEntity.addChild(modelEntity)
                        
                        DispatchQueue.main.async {
                            self.arView.scene.addAnchor(anchorEntity)
                            self.stickerEntities.append((entity: anchorEntity, location: stickerLocation))
                            print("Loaded sticker (world anchor): \(imageName) at distance: \(Int(distance))m")
                        }
                    }
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.isLoading = false
            }
        }
    }
    
    /// Helper function to create a transform matrix from position and rotation
    private func createTransform(position: SIMD3<Float>, rotation: simd_quatf) -> simd_float4x4 {
        let rotationMatrix = matrix_float4x4(rotation)
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1)
        return matrix_multiply(transform, rotationMatrix)
    }
}
