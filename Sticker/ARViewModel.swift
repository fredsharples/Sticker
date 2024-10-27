import SwiftUI
import RealityKit
import ARKit
import CoreLocation
import CoreMotion

class ARViewModel: NSObject, ObservableObject,CLLocationManagerDelegate, ARSessionDelegate {
    @Published var arView: ARView = ARView(frame: .zero)
    let firebaseManager = FirebaseManager()
    let locationManager = CLLocationManager()
    let motionManager = CMMotionManager()
    let pointLight = Entity();
    @Published var currentLocation: CLLocation?
    @Published var heading: CLHeading?
    @Published var motionData: CMDeviceMotion?
    
    private var cameraLight: PointLight?
    private var cameraAnchor: AnchorEntity?
    
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
        setupLighting()
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
    
    
    
    private func setupLighting() {
        // Create camera anchor
        cameraAnchor = AnchorEntity(.camera)
        
        // Create and configure point light
        cameraLight = PointLight()
        cameraLight?.light.color = .white
        cameraLight?.light.intensity = 5000  // Adjust intensity as needed
        cameraLight?.light.attenuationRadius = 5.0  // Adjust radius as needed
        
        // Add light to camera anchor
        if let light = cameraLight, let anchor = cameraAnchor {
            anchor.addChild(light)
            arView.scene.addAnchor(anchor)
        }
    }
    
    private func updateLightPosition() {
        // The light will automatically follow the camera since it's parented to the camera anchor
        // No manual position update needed
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
            anchorEntity.addChild(pointLight)
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
        
        // Keep the same plane mesh generation
        let mesh = MeshResource.generatePlane(width: 0.2, depth: 0.2)
        
        // Create PhysicallyBasedMaterial instead of UnlitMaterial
        var material = PhysicallyBasedMaterial()
        
        do {
            // Load the texture
            guard let texture = try? TextureResource.load(named: img) else {
                print("Failed to load texture: \(img)")
                return ModelEntity()
            }
            let roughnessValue = Float(0.9)
            let blendingValue = Float(0.9)
            let metallicValue = 0.0;
            let opacityValue = Float(0.5);
            let sheenValue = Float(0.5);
            let normalValue = 0.5;
            let environmentLightingWeightValue = Float(0.5);
            let specularValue = 0.5;
            let alphaValue = 0.5;
            let normalMapValue = 0.5;
            let occlusionValue = 0.5;
            let occlusionMapValue = 0.5;
            let normalScaleValue = 0.5;
            let normalMapScaleValue = 0.5;
            let normalMapScaleBiasValue = 0.5;
            let occlusionMapScaleBiasValue = 0.5;
            let normalMapScaleBiasBiasValue = 0.5;
            let occlusionMapScaleBiasBiasValue = 0.5;
            let occlusionMapScaleBiasBiasBiasValue = 0.5;
            
            // Configure the material
            material.baseColor.texture = PhysicallyBasedMaterial.Texture(texture)

            material.roughness = .init(floatLiteral: roughnessValue) // Slightly rough to better catch ambient light
            material.blending = .transparent(opacity: .init(floatLiteral:blendingValue))
            
            //material.metallic = 0.5
            //material.sheen = .init(tint: .white) //bleaches out the sticker
            material.opacityThreshold = 0.5   // For alpha cutout
            //material.clearcoatRoughness = 1.0
            // Set sheen using proper color initialization
            //let sheenColor = SimpleMaterial.Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            //material.sheen = .init(tint: sheenColor)
            // material.sheen = .init(tint: .white)
            //            material.emissiveColor = .init(color: .white)
            //            material.emissiveIntensity = 0.1
            
            //material.baseColor. = 1.5  // Increase the brightness of the texture
            
            // Improve lighting response
            //material.specular. = 0.3   // Add some specularity for better light response
            //            material.clearcoat.value = 0.1  // Slight clearcoat for better light interaction
            //            material.ambient.value = Color.white // Brighten ambient light response
            
            // Enable transparency
            //material.blending = .transparent(opacity: .init(floatLiteral: 0.9))
            
            let modelEntity = ModelEntity(mesh: mesh, materials: [material])
            
            modelEntity.components.set(EnvironmentLightingConfigurationComponent(
                environmentLightingWeight: environmentLightingWeightValue))
            
            
            // Make the ModelEntity double-sided
            if var model = modelEntity.model {
                modelEntity.components.set(EnvironmentLightingConfigurationComponent(
                    environmentLightingWeight: environmentLightingWeightValue))
                model.materials = model.materials.map { material in
                    var newMaterial = material as! PhysicallyBasedMaterial
                    newMaterial.roughness = .init(floatLiteral: roughnessValue)
                    newMaterial.blending = .transparent(opacity: .init(floatLiteral: blendingValue))
                    //newMaterial.sheen = .init(tint: .white)
                    
                    return newMaterial
                }
                modelEntity.model = model
            }
            
            
            return modelEntity
            
        } catch {
            print("Error creating model entity: \(error)")
            return ModelEntity()
        }
    }
    
    
    func saveCurrentAnchor(anchorEntity: AnchorEntity, location: CLLocation) {
        let transformMatrix = anchorEntity.transform.matrix
        let transformArray: [Double] = [
            Double(transformMatrix.columns.0.x), Double(transformMatrix.columns.0.y), Double(transformMatrix.columns.0.z), Double(transformMatrix.columns.0.w),
            Double(transformMatrix.columns.1.x), Double(transformMatrix.columns.1.y), Double(transformMatrix.columns.1.z), Double(transformMatrix.columns.1.w),
            Double(transformMatrix.columns.2.x), Double(transformMatrix.columns.2.y), Double(transformMatrix.columns.2.z), Double(transformMatrix.columns.2.w),
            Double(transformMatrix.columns.3.x), Double(transformMatrix.columns.3.y), Double(transformMatrix.columns.3.z), Double(transformMatrix.columns.3.w)
        ]
        
        var anchorData: [String: Any] = [
            "id": anchorEntity.id.description,
            "transform": transformArray,
            "name": imageName,
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "horizontalAccuracy": location.horizontalAccuracy,
            "verticalAccuracy": location.verticalAccuracy,
            "timestamp": location.timestamp.timeIntervalSince1970
        ]
        
        if let heading = heading {
            anchorData["heading"] = heading.trueHeading
            anchorData["headingAccuracy"] = heading.headingAccuracy
        }
        
        if let motion = motionData {
            anchorData["attitude"] = [
                "roll": motion.attitude.roll,
                "pitch": motion.attitude.pitch,
                "yaw": motion.attitude.yaw
            ]
            anchorData["gravity"] = [
                "x": motion.gravity.x,
                "y": motion.gravity.y,
                "z": motion.gravity.z
            ]
            anchorData["magneticField"] = [
                "x": motion.magneticField.field.x,
                "y": motion.magneticField.field.y,
                "z": motion.magneticField.field.z,
                "accuracy": motion.magneticField.accuracy.rawValue
            ]
        }
        
        firebaseManager.saveAnchor(anchorData: anchorData)
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
}
