import SwiftUI
import RealityKit
import ARKit

class ARViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published var arView: ARView = ARView(frame: .zero)
    let firebaseManager = FirebaseManager();
    
    private var imageAnchor: AnchorEntity?
    private var imageMaterial: UnlitMaterial?
    
    private var placedStickers: [(UUID, Int)] = []
    
    @Published var placedStickersCount: Int = 0
    private var stickers: [AnchorEntity] = []
   // private var currentImageIndex: Int = 1
    private var imageName: String = "";
    @Published  var selectedImageIndex: Int = 1
    
    @Published var currentImageIndex: Int = 1
    
    override init() {
        super.init()
        setupARView();
        firebaseManager.loginFirebase()
    }
    
    // MARK: - Setup
    func setupARView() {
        // Configure ARView and ARSession
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        arView.session.delegate = self
        arView.automaticallyConfigureSession = false
        arView.session.run(configuration)
        
        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        imageName = String(format: "image_%04d", currentImageIndex);
        
    }
    
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: arView)
        let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
        
        if let raycastResult = results.first {
            let anchor = ARAnchor(name: "placedObject", transform: raycastResult.worldTransform)
            arView.session.add(anchor: anchor)
            placedStickers.append((anchor.identifier, currentImageIndex))
        }
    }
    
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if anchor.name == "placedObject" {
                let modelEntity = createModelEntity(imageIndex: currentImageIndex)
                let anchorEntity = AnchorEntity(anchor: anchor)
                anchorEntity.addChild(modelEntity)
                arView.scene.addAnchor(anchorEntity)
            }
        }
    }
    
    // MARK: - Model Creation
    private func createModelEntity(imageIndex: Int) -> ModelEntity {
        
        imageName = String(format: "image_%04d", imageIndex);
        
        let mesh = MeshResource.generatePlane(width: 0.2, depth: 0.2)
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor.white.withAlphaComponent(0.99), texture: .init(try! .load(named: imageName)))
        material.tintColor = UIColor.white.withAlphaComponent(0.99)//F# despite being deprecated this actually honors the alpha where the above does not
        let modelEntity = ModelEntity(mesh: mesh, materials: [material])
        return modelEntity
    }
    
    func saveCurrentAnchor() {
        guard let lastAnchor = arView.session.currentFrame?.anchors.last else {
            print("No anchor to save.")
            return
        }
        firebaseManager.saveAnchor(anchor: lastAnchor, imageName: imageName)
    }
    
    func loadSavedAnchors() {
        firebaseManager.loadAnchors { [weak self] anchors in
            guard let self = self else { return }
            for anchorData in anchors {
                let anchor = anchorData.toARAnchor()
                self.arView.session.add(anchor: anchor)
            }
            
        }
    }
    
    // MARK: - Clear All Anchors and Models
    
    func clearAll() {
        // Remove all anchors from the AR session
        arView.session.getCurrentWorldMap { [weak self] worldMap, error in
            guard let self = self else { return }
            if let error = error {
                print("Error getting current world map: \(error.localizedDescription)")
                return
            }
            
            guard worldMap != nil else {
                print("No world map available.")
                return
            }
            
            // Create a new ARWorldTrackingConfiguration
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            
            // Run the session with a reset tracking and remove existing anchors
            self.arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            
            // Optionally, you can clear the scene
            self.arView.scene.anchors.removeAll()
            
            print("All anchors and models have been cleared from the AR view.")
        }
    }
    
    func setSelectedImage(imageIndex: Int) {
        currentImageIndex = imageIndex
        
    }
    
}

