import SwiftUI
import RealityKit
import ARKit
import CoreLocation
import CoreMotion

class ARViewModel: NSObject, ObservableObject,CLLocationManagerDelegate {
    @Published var arView: ARView = ARView(frame: .zero)
    let firebaseManager = FirebaseManager()
    let locationManager = CLLocationManager()
    let motionManager = CMMotionManager()
    
    private var stickerEntities: [(entity: AnchorEntity, location: CLLocation)] = []
    
    @Published var currentLocation: CLLocation?
    @Published var heading: CLHeading?
    @Published var motionData: CMDeviceMotion?
    
    
    private var imageName: String = ""
    
    @Published var selectedImageIndex: Int = 1
    
    override init() {
        super.init()
        setupARView()
        setupLocationManager()
        setupMotionManager()
        initializeFirebase()
    }
    
    /// Initializes Firebase authentication and loads saved anchors
    private func initializeFirebase() {
        firebaseManager.loginFirebase { [weak self] result in
            switch result {
            case .success(let user):
                print("Logged in as user: \(user.uid)")
                self?.loadSavedAnchors()
            case .failure(let error):
                print("Failed to log in: \(error.localizedDescription)")
            }
        }
    }
    
    func setupMotionManager() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.1
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
                guard let motion = motion, error == nil else { return }
                self?.motionData = motion
            }
        }
    }
    
    
    func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    //Delegate for updating location
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        
        // When location updates, check if we should load or unload stickers
        updateVisibleStickers()
    }
    
    //delegate for updating compass heading
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }
    
    private func updateVisibleStickers() {
        guard let currentLocation = currentLocation else { return }
        
        // Remove stickers that are too far away
        stickerEntities.forEach { entity, location in
            let distance = location.distance(from: currentLocation)
            if distance > 100 { // 100 meters threshold
                arView.scene.removeAnchor(entity)
            }
        }
        stickerEntities.removeAll { _, location in
            location.distance(from: currentLocation) > 100
        }
        
        // Load new nearby stickers
        fetchNearbyStickerLocations()
    }
    
    
    private func fetchNearbyStickerLocations() {
        guard let userLocation = currentLocation else {
            print("Current location not available")
            return
        }
        
        firebaseManager.fetchNearbyStickerData(
            latitude: userLocation.coordinate.latitude,
            longitude: userLocation.coordinate.longitude,
            radiusInKm: 0.1  // 100 meters
        ) { [weak self] stickerData in
            self?.handleReceivedStickerData(stickerData)
        }
    }
    
    // MARK: - Setup
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
    
    // MARK: - Tap
    /// Handles tap gestures for placing stickers in AR space
    @objc private func handleTap(_ sender: UITapGestureRecognizer) {
        guard let currentLocation = currentLocation else { return }
        
        let location = sender.location(in: arView)
        let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
        
        if let raycastResult = results.first {
            let anchorEntity = AnchorEntity()
            anchorEntity.name = "placedObject"
            anchorEntity.setTransformMatrix(raycastResult.worldTransform, relativeTo: nil)
            
            let imageName = String(format: "image_%04d", selectedImageIndex)
            let modelEntity = createModelEntity(img: imageName)
            anchorEntity.addChild(modelEntity)
            arView.scene.addAnchor(anchorEntity)
            
            saveStickerToFirebase(anchorEntity: anchorEntity, location: currentLocation)
        }
    }
    /// Saves sticker data to Firebase
    private func saveStickerToFirebase(anchorEntity: AnchorEntity, location: CLLocation) {
        let transformArray = transformToArray(anchorEntity.transform.matrix)
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
        
        firebaseManager.saveSticker(data: stickerData) { result in
            switch result {
            case .success:
                print("Sticker saved successfully")
            case .failure(let error):
                print("Failed to save sticker: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleReceivedStickerData(_ stickerData: [String: Any]) {
        guard let stickerLat = stickerData["latitude"] as? Double,
              let stickerLon = stickerData["longitude"] as? Double,
              let transform = stickerData["transform"] as? [Double],
              let imageName = stickerData["name"] as? String,
              let currentLocation = self.currentLocation else {
            return
        }
        
        let stickerLocation = CLLocation(
            latitude: stickerLat,
            longitude: stickerLon
        )
        
        // Check if we already have this sticker loaded
        let stickerID = stickerData["id"] as? String
        if stickerEntities.contains(where: { $0.entity.id.description == stickerID }) {
            return
        }
        
        // Only load if within range
        let distance = stickerLocation.distance(from: currentLocation)
        if distance <= 100 { // 100 meters
            let transformMatrix = simd_float4x4(rows: [
                SIMD4<Float>(Float(transform[0]), Float(transform[1]), Float(transform[2]), Float(transform[3])),
                SIMD4<Float>(Float(transform[4]), Float(transform[5]), Float(transform[6]), Float(transform[7])),
                SIMD4<Float>(Float(transform[8]), Float(transform[9]), Float(transform[10]), Float(transform[11])),
                SIMD4<Float>(Float(transform[12]), Float(transform[13]), Float(transform[14]), Float(transform[15]))
            ])
            
            let anchorEntity = AnchorEntity(world: transformMatrix)
            let modelEntity = createModelEntity(img: imageName)
            anchorEntity.addChild(modelEntity)
            arView.scene.addAnchor(anchorEntity)
            
            stickerEntities.append((entity: anchorEntity, location: stickerLocation))
        }
    }
    
    func getDistanceToNearestSticker() -> Double? {
        guard let userLocation = currentLocation else { return nil }
        
        let distances = stickerEntities.map { _, location in
            location.distance(from: userLocation)
        }
        
        return distances.min()
    }
    
    // MARK: - Model Creation
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
    
    //MARK: - Save and Retrieve
    func saveCurrentAnchor(anchorEntity: AnchorEntity, location: CLLocation) {
        let transformMatrix = anchorEntity.transform.matrix
        //let transformArray = transformMatrix.columns.flatMap { $0.map(Double.init) }
        let transformArray: [Double] = [
            Double(transformMatrix.columns.0[0]), Double(transformMatrix.columns.0[1]),
            Double(transformMatrix.columns.0[2]), Double(transformMatrix.columns.0[3]),
            Double(transformMatrix.columns.1[0]), Double(transformMatrix.columns.1[1]),
            Double(transformMatrix.columns.1[2]), Double(transformMatrix.columns.1[3]),
            Double(transformMatrix.columns.2[0]), Double(transformMatrix.columns.2[1]),
            Double(transformMatrix.columns.2[2]), Double(transformMatrix.columns.2[3]),
            Double(transformMatrix.columns.3[0]), Double(transformMatrix.columns.3[1]),
            Double(transformMatrix.columns.3[2]), Double(transformMatrix.columns.3[3])
        ]
        // Capture current frame for feature extraction
        guard let currentFrame = arView.session.currentFrame else { return }
        
        var stickerData: [String: Any] = [
            "id": anchorEntity.id.description,
            "transform": transformArray,
            "name": imageName,
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "horizontalAccuracy": location.horizontalAccuracy,
            "verticalAccuracy": location.verticalAccuracy,
            "timestamp": location.timestamp.timeIntervalSince1970,
            "deviceOrientation": [
                "pitch": currentFrame.camera.eulerAngles.x,
                "yaw": currentFrame.camera.eulerAngles.y,
                "roll": currentFrame.camera.eulerAngles.z
            ]
        ]
        
        // Extract visual features
        //           if let features = extractVisualFeatures(from: currentFrame) {
        //               stickerData["visualFeatures"] = features
        //           }
        
        // Save plane characteristics if available
        if let planeAnchor = anchorEntity.anchor as? ARPlaneAnchor {
            stickerData["planeCharacteristics"] = [
                "center": [planeAnchor.center.x, planeAnchor.center.y, planeAnchor.center.z],
                "extent": [planeAnchor.extent.x, planeAnchor.extent.y, planeAnchor.extent.z],
                "alignment": planeAnchor.alignment.rawValue
            ]
        }
        
        firebaseManager.saveSticker(data: stickerData) { result in
            switch result {
            case .success:
                print("Sticker saved successfully")
            case .failure(let error):
                print("Failed to save sticker: \(error.localizedDescription)")
            }
        }
        
        
    }
    
    func loadSavedAnchors() {
        firebaseManager.loadAnchors { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let anchors):
                DispatchQueue.main.async {
                    for anchorData in anchors {
                        // Convert AnchorData to AnchorEntity
                        let anchorEntity = anchorData.toAnchorEntity()
                        
                        // Create the ModelEntity
                        let modelEntity = self.createModelEntity(img: anchorData.name)
                        print("Retrieved Sticker: \(anchorData.name)")
                        
                        // Add the ModelEntity to the AnchorEntity
                        anchorEntity.addChild(modelEntity)
                        
                        // Add the AnchorEntity to the scene
                        self.arView.scene.addAnchor(anchorEntity)
                        
                        
                    }
                }
            case .failure(let error):
                print("Failed to load anchors: \(error.localizedDescription)")
                // Optionally, update the UI to reflect the error
            }
        }
    }
    
    // MARK: - Clear All Anchors and Models from Scene
    /// Clears all stickers from the AR scene
    func clearAll() {
        arView.scene.anchors.removeAll()
        stickerEntities.removeAll()
    }
    
    func deleteAllfromFirebase() {
        firebaseManager.deleteAllAnchors { result in
            switch result {
            case .success:
                print("All anchors have been deleted from Firebase")
                // Optionally update your local state or UI here
            case .failure(let error):
                print("Failed to delete anchors: \(error.localizedDescription)")
                // Handle the error appropriately
            }
        }
    }
    
    //MARK: - Utilities
    func setSelectedImage(imageIndex: Int) {
        selectedImageIndex = imageIndex
        print("Picked Sticker number: \(selectedImageIndex)")
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
}
