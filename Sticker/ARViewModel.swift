import SwiftUI
import RealityKit
import ARKit
import FocusEntity

class ARViewModel: NSObject, ObservableObject {
    @Published var arView: ARView = ARView(frame: .zero)
    let firebaseManager = FirebaseManager()
    
    var focusEntity: FocusEntity?
    
    private var placedStickers: [(UUID, Int)] = []
    private var anchorEntities: [AnchorEntity] = [] // Tracking array
    
    private var imageName: String = ""
    @Published var selectedImageIndex: Int = 1
    
    override init() {
        super.init()
        self.setUpFocusEntity()
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
    }
    
    func setUpFocusEntity() {
        self.focusEntity = FocusEntity(on: arView, style: .classic(color: .white))
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
        let location = sender.location(in: arView)
        let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
        
        if let raycastResult = results.first {
            let worldTransform = raycastResult.worldTransform
            // Debug: Print the raycast result's transform
            print("Raycast Result Transform: \(worldTransform)")
            
            // Create AnchorEntity at the world origin
            let anchorEntity = AnchorEntity()
            anchorEntity.name = "placedObject"
            
            // Set the transform of the AnchorEntity
            anchorEntity.setTransformMatrix(worldTransform, relativeTo: nil)
            
            // Debug: Print the anchor's transform after setting
            print("Anchor Transform After Setting: \(anchorEntity.transform.matrix)")
            
            imageName = String(format: "image_%04d", selectedImageIndex)
            
            // Create and add the ModelEntity
            let modelEntity = createModelEntity(img: imageName)
            anchorEntity.addChild(modelEntity)
            
            // Add the AnchorEntity to the scene
            arView.scene.addAnchor(anchorEntity)
            
            // Debug: Print confirmation of anchor addition
            print("AnchorEntity added to scene with ID: \(anchorEntity.id)")
            
            // Keep track of placed stickers
            anchorEntities.append(anchorEntity) // Track the anchor
            print("handleTap called with Image Number: \(selectedImageIndex)")
            saveCurrentAnchor()
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
    
    
    func saveCurrentAnchor() {
        guard let lastAnchor = anchorEntities.last else {
            print("No anchor to save.")
            return
        }
        firebaseManager.saveAnchor(anchor: lastAnchor, imageName: imageName)
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
        setUpFocusEntity()
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
