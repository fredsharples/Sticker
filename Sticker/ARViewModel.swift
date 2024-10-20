import SwiftUI
import RealityKit
import ARKit
import CoreLocation

class ARViewModel: NSObject, ObservableObject,CLLocationManagerDelegate {
    @Published var arView: ARView = ARView(frame: .zero)
    let firebaseManager = FirebaseManager()
    let locationManager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    
    
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
    }
    
    func setupLocationManager() {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
        }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
           currentLocation = locations.last
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
            let transformArray: [Double] = [
                Double(transformMatrix.columns.0.x), Double(transformMatrix.columns.0.y), Double(transformMatrix.columns.0.z), Double(transformMatrix.columns.0.w),
                Double(transformMatrix.columns.1.x), Double(transformMatrix.columns.1.y), Double(transformMatrix.columns.1.z), Double(transformMatrix.columns.1.w),
                Double(transformMatrix.columns.2.x), Double(transformMatrix.columns.2.y), Double(transformMatrix.columns.2.z), Double(transformMatrix.columns.2.w),
                Double(transformMatrix.columns.3.x), Double(transformMatrix.columns.3.y), Double(transformMatrix.columns.3.z), Double(transformMatrix.columns.3.w)
            ]
            
            let anchorData: [String: Any] = [
                "id": anchorEntity.id.description,
                "transform": transformArray,
                "name": imageName,
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "altitude": location.altitude
            ]
            
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
