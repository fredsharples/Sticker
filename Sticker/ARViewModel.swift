import SwiftUI
import RealityKit
import ARKit

class ARViewModel: NSObject, ObservableObject, ARSessionDelegate {
   // @Published var arView: ARView?
    @Published var arView: ARView = ARView(frame: .zero)
    
    let firebaseManager = FirebaseManager();
    
    private var imageAnchor: AnchorEntity?
    private var imageMaterial: UnlitMaterial?
    
    private var placedStickers: [(UUID, Int)] = []
    
    @Published var placedStickersCount: Int = 0
    private var stickers: [AnchorEntity] = []
    private var currentImageIndex: Int = 1
    private let maxStickers = 100
    
    
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
    }
    
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: arView)
               let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
               
               if let raycastResult = results.first {
                   let anchor = ARAnchor(name: "placedObject", transform: raycastResult.worldTransform)
                   arView.session.add(anchor: anchor)
               }
    }
    
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                if anchor.name == "placedObject" {
                    let modelEntity = createModelEntity()
                    let anchorEntity = AnchorEntity(anchor: anchor)
                    anchorEntity.addChild(modelEntity)
                    arView.scene.addAnchor(anchorEntity)
                }
            }
        }
    
    // MARK: - Model Creation
    private func createModelEntity() -> ModelEntity {
        
        let mesh = MeshResource.generatePlane(width: 0.2, depth: 0.2)
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor.white.withAlphaComponent(0.99), texture: .init(try! .load(named: String(format: "image_%04d", currentImageIndex))))
        material.tintColor = UIColor.white.withAlphaComponent(0.99)//F# despite being deprecated this actually honors the alpha where the above does not
        
        
        let modelEntity = ModelEntity(mesh: mesh, materials: [material])
        
           return modelEntity
       }
    
    func setSelectedImage(imageIndex: Int) {
        currentImageIndex = imageIndex
       // imageMaterial = createMaterialForImage();
    }
    
    private func createMaterialForImage() -> UnlitMaterial? {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor.white.withAlphaComponent(0.99), texture: .init(try! .load(named: String(format: "image_%04d", currentImageIndex))))
        material.tintColor = UIColor.white.withAlphaComponent(0.99)//F# despite being deprecated this actually honors the alpha where the above does not
        return material
    }
    
    func saveCurrentAnchor() {
            guard let lastAnchor = arView.session.currentFrame?.anchors.last else {
                print("No anchor to save.")
                return
            }
            firebaseManager.saveAnchor(anchor: lastAnchor)
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
    
//    func startARSession() {
//        guard let arView = arView else { return }
//        
//        let config = ARWorldTrackingConfiguration()
//        config.planeDetection = [.horizontal, .vertical]
//        config.environmentTexturing = .automatic
//        
//        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
//            config.sceneReconstruction = .mesh
//        }    
//        
//        
//        arView.session.run(config, options: [.removeExistingAnchors, .resetTracking])
//        if(stickers.isEmpty){
//            retreivePlacedStickers()
//        }else{
//            restorePlacedStickers()
//        }
//        
//    }
    ///////
//    func savePlaneTransform(_ planeEntity: ModelEntity) -> [String: Any] {
//        // Get the plane's transform matrix
//        let transform = planeEntity.transform.matrix
//        
//        // Serialize the matrix into an array
//        let transformArray = [
//            transform.columns.0.x, transform.columns.0.y, transform.columns.0.z, transform.columns.0.w,
//            transform.columns.1.x, transform.columns.1.y, transform.columns.1.z, transform.columns.1.w,
//            transform.columns.2.x, transform.columns.2.y, transform.columns.2.z, transform.columns.2.w,
//            transform.columns.3.x, transform.columns.3.y, transform.columns.3.z, transform.columns.3.w
//        ]
//        
//        // Prepare data for storage
//        let planeData: [String: Any] = [
//            "transform": transformArray
//        ]
//        
//        return planeData
//    }
    
    
//    func saveCurrentWorldMap(session: ARSession) {
//        session.getCurrentWorldMap { worldMap, error in
//            guard let worldMap = worldMap else {
//                print("Error getting current world map: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//            
//            // Serialize the ARWorldMap
//            if (try? NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)) != nil {
//                // Save 'data' to persistent storage
//            }
//        }
//    }
    
//    func loadWorldMap() -> ARWorldMap? {
//        // Retrieve 'data' from persistent storage
//        if let data = /* your data retrieval code */,
//           let worldMap = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) {
//            return worldMap
//        }
//        return nil
//    }
    
 
    
//    func placeSticker(at result: ARRaycastResult) {
//        guard let arView = arView else { return }
//        
//        if placedStickers.count >= maxStickers {
//            print("Maximum number of images reached")
//            return
//        }
//        //let anchorEntity = AnchorEntity(anchor: anchor)
//        let anchor = ARAnchor(name: "ImageAnchor", transform: result.worldTransform)
//        let anchorEntity = AnchorEntity(anchor: anchor)
//        arView.session.add(anchor: anchor)
//        stickers.append(anchorEntity)
//        placedStickers.append((anchor.identifier, currentStickerIndex))
//        placedStickersCount = placedStickers.count
//        
//        addStickerToScene(anchor: anchor, imageIndex: currentStickerIndex)
//    }
    
    
//    private func addStickerToScene(anchor: ARAnchor, imageIndex: Int) {
//        guard let arView = arView, let material = createMaterialForImage(imageIndex: imageIndex) else { return }
//        let anchorEntity = AnchorEntity(anchor: anchor)
//        let mesh = MeshResource.generatePlane(width: 0.2, depth: 0.2)
//        let imageEntity = ModelEntity(mesh: mesh, materials: [material])
//        anchorEntity.addChild(imageEntity)
//        arView.scene.addAnchor(anchorEntity)
//        
//    }
    
    func clearAllStickers() {
        
        for (anchorID, _) in placedStickers {
            if let anchor = arView.session.currentFrame?.anchors.first(where: { $0.identifier == anchorID }) {
                arView.session.remove(anchor: anchor)
            }
        }
        placedStickers.removeAll()
        placedStickersCount = 0
    }
    
//    func restorePlacedStickers() {
//        guard let arView = arView else { return }
//        
//        for (anchorID, imageIndex) in placedStickers{
//            if let anchor = arView.session.currentFrame?.anchors.first(where: { $0.identifier == anchorID }) {
//                addStickerToScene(anchor: anchor, imageIndex: imageIndex)
//            }
//        }
//    }
    
//    func savePlacedStickers() {
//        print("Save placed stickers called")
//        AuthManager.shared.signInAnonymously { result in
//            switch result {
//            case .success(let user):
//                print("User signed in anonymously with ID: \(user.uid)")
//                
//                self.firebaseManager.saveAnchorEntities(self.stickers, completion: { result in
//                    switch result {
//                    case .success:
//                        print("Anchors saved successfully")
//                    case .failure(let error):
//                        print("Error saving anchors: \(error.localizedDescription)")
//                    }
//                })
//            case .failure(let error):
//                print("Error signing in: \(error.localizedDescription)")
//            }
//        }
//    }
    /////
    ///
    func createAnchor(at transform: simd_float4x4) -> ARAnchor {
        let anchor = ARAnchor(transform: transform)
        return anchor
    }
    
    func restoreAnchors(_ anchorsData: [[String: Any]]) {
        for anchorData in anchorsData {
            if let transformArray = anchorData["transform"] as? [Float] {
                // Reconstruct the transform matrix
                let transform = simd_float4x4(
                    SIMD4<Float>(transformArray[0], transformArray[1], transformArray[2], transformArray[3]),
                    SIMD4<Float>(transformArray[4], transformArray[5], transformArray[6], transformArray[7]),
                    SIMD4<Float>(transformArray[8], transformArray[9], transformArray[10], transformArray[11]),
                    SIMD4<Float>(transformArray[12], transformArray[13], transformArray[14], transformArray[15])
                )
                
                let anchor = ARAnchor(transform: transform)
                arView.session.add(anchor: anchor)
            }
        }
    }
    
    
    
//    func retreivePlacedStickers() {
//        AuthManager.shared.signInAnonymously { result in
//            switch result {
//            case .success(let user):
//                print("User signed in anonymously with ID: \(user.uid)")
//                self.firebaseManager.loadAnchorEntities { result in
//                                    switch result {
//                                    case .success(let loadedAnchors):
//                                        DispatchQueue.main.async {
//                                            self.stickers = loadedAnchors
//                                        }
//                                        print("Anchors loaded successfully")
//                                    case .failure(let error):
//                                        print("Error loading anchors: \(error.localizedDescription)")
//                                    }
//                                }
//            case .failure(let error):
//                print("Error signing in: \(error.localizedDescription)")
//            }
//        }
//    }
    
}


//extension ARViewModel: ARSessionDelegate {
//    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
//        for anchor in anchors {
//            if anchor is ARPlaneAnchor {
//                // A plane has been detected
//                print("New plane detected")
//                
//                if let imageAnchor = placedStickers.first(where: { $0.0 == anchor.identifier }) {
//                    addStickerToScene(anchor: anchor, imageIndex: imageAnchor.1)
//                }
//            }
//        }
//    }
//}


