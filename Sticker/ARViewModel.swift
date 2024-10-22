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
    
    @Published var currentLocation: CLLocation?
    @Published var heading: CLHeading?
    @Published var motionData: CMDeviceMotion?
    
    
    private var placedStickers: [(UUID, Int)] = []
    private var anchorEntities: [AnchorEntity] = [] // Tracking array
    
    private var imageName: String = ""
    @Published var selectedImageIndex: Int = 1
    
    override init() {
        super.init()
        // self.setUpFocusEntity()
        setupARView()
        firebaseManager.loginFirebase { result in
            switch result {
            case .success(let user):
                print("Logged in as user: \(user.uid)")
                // Optionally, load saved anchors here
                self.loadSavedAnchors()
            case .failure(let error):
                print("Failed to log in: \(error.localizedDescription)")
            }
        }
        setupLocationManager()
        setupMotionManager()
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
        locationManager.pausesLocationUpdatesAutomatically = false
        
        if #available(iOS 11.0, *) {
            locationManager.showsBackgroundLocationIndicator = true
        }
        
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    //Delegate for updating location
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
           guard let location = locations.last else { return }
           
           // Filter out inaccurate locations
           if location.horizontalAccuracy < 20 {
               currentLocation = location
           }
       }
    //delegate for updating compass heading
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
           heading = newHeading
       }
    
    func discoverAndRenderStickers() {
            guard let currentLocation = locationManager.location else { return }
            
            // Fetch nearby stickers from Firebase based on current location
        firebaseManager.fetchNearbyStickerData(latitude: currentLocation.coordinate.latitude,
                                               longitude: currentLocation.coordinate.longitude,
                                               radiusInKm: 0.1) { [weak self] stickerData in
            guard let self = self else { return }
            self.attemptToRenderSticker(stickerData: stickerData)
        }
        }
    
    private func attemptToRenderSticker(stickerData: [String: Any]) {
            guard let transform = stickerData["transform"] as? [Double],
                  transform.count == 16,
                  let imageName = stickerData["name"] as? String else { return }
            
            let transformMatrix = simd_float4x4(rows: [
                SIMD4<Float>(Float(transform[0]), Float(transform[1]), Float(transform[2]), Float(transform[3])),
                SIMD4<Float>(Float(transform[4]), Float(transform[5]), Float(transform[6]), Float(transform[7])),
                SIMD4<Float>(Float(transform[8]), Float(transform[9]), Float(transform[10]), Float(transform[11])),
                SIMD4<Float>(Float(transform[12]), Float(transform[13]), Float(transform[14]), Float(transform[15]))
            ])
            
            // Check if we can detect a similar plane
            if let planeCharacteristics = stickerData["planeCharacteristics"] as? [String: Any],
               let detectedPlane = findSimilarPlane(characteristics: planeCharacteristics) {
                renderStickerOnPlane(imageName: imageName, transform: transformMatrix, plane: detectedPlane)
            } else {
                // If no similar plane found, try visual feature matching
                if let visualFeatures = stickerData["visualFeatures"] as? [[Float]],
                   let matchedTransform = matchVisualFeatures(features: visualFeatures) {
                    renderStickerAtTransform(imageName: imageName, transform: matchedTransform)
                } else {
                    // If all else fails, use the original transform with a warning about potential inaccuracy
                    renderStickerAtTransform(imageName: imageName, transform: transformMatrix, isAccurate: false)
                }
            }
        }
    
    private func findSimilarPlane(characteristics: [String: Any]) -> ARPlaneAnchor? {
            // Implementation to find a similar plane based on saved characteristics
            // This would involve comparing the current ARSession's detected planes with the saved characteristics
            // Return the most similar ARPlaneAnchor if found, nil otherwise
            return nil // Placeholder
        }
        
        private func matchVisualFeatures(features: [[Float]]) -> simd_float4x4? {
            // Implementation to match visual features and calculate a transform
            // This would involve capturing the current frame, extracting features, and comparing with saved features
            // Return a transform if a good match is found, nil otherwise
            return nil // Placeholder
        }
        
        private func renderStickerOnPlane(imageName: String, transform: simd_float4x4, plane: ARPlaneAnchor) {
            let adjustedTransform = transform * plane.transform
            renderStickerAtTransform(imageName: imageName, transform: adjustedTransform)
        }
        
        private func renderStickerAtTransform(imageName: String, transform: simd_float4x4, isAccurate: Bool = true) {
            let anchorEntity = AnchorEntity(world: transform)
            let modelEntity = createModelEntity(img: imageName)
            anchorEntity.addChild(modelEntity)
            
            if !isAccurate {
                // Add some visual indication that the placement might not be accurate
                let warningEntity = ModelEntity(mesh: .generateText("⚠️ Approximate location", extrusionDepth: 0.1, font: .systemFont(ofSize: 0.2), containerFrame: .zero, alignment: .center, lineBreakMode: .byWordWrapping))
                warningEntity.setPosition([0, 0.3, 0], relativeTo: modelEntity)
                anchorEntity.addChild(warningEntity)
            }
            
            arView.scene.addAnchor(anchorEntity)
        }
    // MARK: - Setup
    func setupARView() {
        // Configure ARView and ARSession
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        }
        arView.automaticallyConfigureSession = false
        arView.session.run(configuration)
        
        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        imageName = String(format: "image_%04d", selectedImageIndex)
    }
    
    // MARK: - Tap
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        guard let currentLocation = currentLocation else {
            print("Current location not available")
            return
        }
        
        let location = sender.location(in: arView)
        let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
        
        if let raycastResult = results.first {
            let worldTransform = raycastResult.worldTransform
            
            let anchorEntity = AnchorEntity()
            anchorEntity.name = "placedObject"
            
            anchorEntity.setTransformMatrix(worldTransform, relativeTo: nil)
            
            imageName = String(format: "image_%04d", selectedImageIndex)
            
            let modelEntity = createModelEntity(img: imageName)
            anchorEntity.addChild(modelEntity)
            
            arView.scene.addAnchor(anchorEntity)
            
            anchorEntities.append(anchorEntity)
            
            // Save anchor with geolocation
            saveCurrentAnchor(anchorEntity: anchorEntity, location: currentLocation)
        } else {
            print("No valid raycast result found.")
        }
    }
    
    // MARK: - Model Creation
    private func createModelEntity(img: String) -> ModelEntity {
        print("Creating Model with: \(img)")
        
        let mesh = MeshResource.generatePlane(width: 0.2, depth: 0.2)
        
        guard let texture = try? TextureResource.load(named: img) else {
            print("Failed to load texture: \(img)")
            return ModelEntity()
        }
        
        var material = UnlitMaterial()
        
        //cannot use color attribute with a texture so using deprecated baseColor which displays the bitmap with transparency
        material.baseColor = MaterialColorParameter.texture(texture)
        
        // Enable transparency
        material.blending = .transparent(opacity: .init(floatLiteral: 1.0))
        
        let modelEntity = ModelEntity(mesh: mesh, materials: [material])
        
        // Make the ModelEntity double-sided
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
    
    
    func saveCurrentAnchor(anchorEntity: AnchorEntity, location: CLLocation) {
           let transformMatrix = anchorEntity.transform.matrix
           let transformArray = transformMatrix.columns.flatMap { $0.map(Double.init) }
           
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
           if let features = extractVisualFeatures(from: currentFrame) {
               stickerData["visualFeatures"] = features
           }
           
           // Save plane characteristics if available
           if let planeAnchor = anchorEntity.anchor as? ARPlaneAnchor {
               stickerData["planeCharacteristics"] = [
                   "center": [planeAnchor.center.x, planeAnchor.center.y, planeAnchor.center.z],
                   "extent": [planeAnchor.extent.x, planeAnchor.extent.y, planeAnchor.extent.z],
                   "alignment": planeAnchor.alignment.rawValue
               ]
           }
           
           firebaseManager.saveAnchor(anchorData: stickerData)
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
                        
                        // Track the loaded anchor
                        self.anchorEntities.append(anchorEntity)
                    }
                }
            case .failure(let error):
                print("Failed to load anchors: \(error.localizedDescription)")
                // Optionally, update the UI to reflect the error
            }
        }
    }
    
    // MARK: - Clear All Anchors and Models from Scene
    func clearAll() {
        // Clear the scene
        arView.scene.anchors.removeAll()
        
        // Reset the tracking array
        anchorEntities.removeAll()
        
        // Reset the focusEntity (reticle)
        //setUpFocusEntity()
        print("All anchors and models have been cleared from the AR view.")
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
    
    func setSelectedImage(imageIndex: Int) {
        selectedImageIndex = imageIndex
        print("Picked Sticker number: \(selectedImageIndex)")
    }
    
    private func extractVisualFeatures(from frame: ARFrame) -> [[Float]]? {
            guard let pixelBuffer = frame.capturedImage else { return nil }
            
            let request = VNDetectImageFeaturesRequest()
            let handler = VNImageRequestHandler(ciImage: CIImage(cvPixelBuffer: pixelBuffer), orientation: .up)
            
            do {
                try handler.perform([request])
                if let results = request.results as? [VNFeature],
                   let firstResult = results.first,
                   let points = firstResult.points {
                    return points.map { [$0.x, $0.y] }
                }
            } catch {
                print("Failed to extract visual features: \(error)")
            }
            
            return nil
        }
}
