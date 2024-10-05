import SwiftUI
import RealityKit
import ARKit
import FirebaseFirestore
class ARViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published var arView: ARView = ARView(frame: .zero)
    let firestoreManager = FirestoreManager();
    
    private var imageAnchor: AnchorEntity?
    private var imageMaterial: UnlitMaterial?
    
    private var placedStickers: [(UUID, Int)] = []
    
    @Published var placedStickersCount: Int = 0
    private var stickers: [AnchorEntity] = []
    private var currentImageIndex: Int = 1
    private let maxStickers = 100
    
    private var anchorMaterials: [UUID: MaterialData] = [:]
    
    
    override init() {
        super.init()
        setupARView();
        firestoreManager.loginFirebase()
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
    
    @objc private func handleTap(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: arView)
        let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
        
        if let raycastResult = results.first {
            // Assume you have a method to get the current image index
            //let imageIndex = currentImageIndex
            let anchorName = "placedObject_\(currentImageIndex)"
            let anchor = ARAnchor(name: anchorName, transform: raycastResult.worldTransform)
            arView.session.add(anchor: anchor)
        }
    }
    
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            var imageIndex = 1
            var tintAlpha: CGFloat = 0.99
            
            if let materialData = anchorMaterials[anchor.identifier] {
                imageIndex = materialData.imageIndex
                tintAlpha = CGFloat(materialData.tintAlpha)
            } else if let name = anchor.name, let index = extractImageIndex(from: name) {
                imageIndex = index
            }
            
            let modelEntity = createModelEntity(imageIndex: imageIndex, tintAlpha: tintAlpha)
            let anchorEntity = AnchorEntity(anchor: anchor)
            anchorEntity.addChild(modelEntity)
            arView.scene.addAnchor(anchorEntity)
        }
    }
    
    // MARK: - Model Creation
    func createModelEntity(imageIndex: Int, tintAlpha: CGFloat) -> ModelEntity {
        let mesh = MeshResource.generatePlane(width: 1.0, height: 1.0)
        var material = UnlitMaterial()
        let textureName = String(format: "image_%04d", imageIndex)
        
        do {
            let texture = try TextureResource.load(named: textureName)
            material.color = .init(tint: UIColor.white.withAlphaComponent(tintAlpha), texture: .init(texture))
        } catch {
            print("Error loading texture: \(error.localizedDescription)")
            material.color = .init(tint: UIColor.white.withAlphaComponent(tintAlpha))
        }
        
        let modelEntity = ModelEntity(mesh: mesh, materials: [material])
        modelEntity.name = "ModelEntity_\(imageIndex)"
        
        return modelEntity
    }
    
    
    
    func loadSavedAnchors() {
        firestoreManager.loadAnchors { [weak self] anchors in
            guard let self = self else { return }

            for anchorData in anchors {
                let anchor = anchorData.toARAnchor()
                self.arView.session.add(anchor: anchor)
                if let materialData = anchorData.materialData {
                    self.anchorMaterials[anchor.identifier] = materialData
                }
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
    
    // Helper function to extract imageIndex from texture name
    func extractImageIndex(from name: String) -> Int? {
        // Assuming names are in the format "placedObject_XXXX"
        let pattern = #"placedObject_(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: name, options: [], range: NSRange(location: 0, length: name.utf16.count)),
           let range = Range(match.range(at: 1), in: name) {
            let indexString = String(name[range])
            return Int(indexString)
        }
        return nil
    }
    
    func setSelectedImage(imageIndex: Int) {
        currentImageIndex = imageIndex
        
    }
    
    // MARK: - Save Current Anchor with Material Data
        
    func saveCurrentAnchor() {
        guard let lastAnchor = arView.session.currentFrame?.anchors.last else {
            print("No anchor to save.")
            return
        }
        
        // Extract imageIndex from the anchor's name
        var imageIndex: Int = 0
        if let name = lastAnchor.name,
           let index = extractImageIndex(from: name) {
            imageIndex = index
        } else {
            print("Unable to extract imageIndex from anchor's name.")
        }
        
        // Retrieve the AnchorEntity associated with the ARAnchor
        guard let anchorEntity = arView.scene.anchors.first(where: { $0.anchorIdentifier == lastAnchor.identifier }) else {
            print("No AnchorEntity found for the last anchor.")
            firestoreManager.saveAnchor(anchor: lastAnchor, materialData: nil)
            return
        }
        
        // Retrieve the ModelEntity attached to the AnchorEntity
        guard let modelEntity = anchorEntity.children.first as? ModelEntity else {
            print("No ModelEntity found in the anchor entity.")
            firestoreManager.saveAnchor(anchor: lastAnchor, materialData: nil)
            return
        }
        
        // Get the tintAlpha value from the material's color tint
        guard let material = modelEntity.model?.materials.first as? UnlitMaterial else {
            print("No UnlitMaterial found in the model entity.")
            firestoreManager.saveAnchor(anchor: lastAnchor, materialData: nil)
            return
        }
        
        // Since 'tint' is a non-optional UIColor, we can access it directly
        let tintColor = material.color.tint
        let tintAlpha = Float(tintColor.cgColor.alpha)
        let materialDict: [String: Any] = [
            "imageIndex": imageIndex,
            "tintAlpha": tintAlpha
        ]
        // Create MaterialData with the extracted properties
        let materialData = MaterialData(dictionary: materialDict)
        
        // Save the anchor along with the material data
        firestoreManager.saveAnchor(anchor: lastAnchor, materialData: materialData)
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
    
    
    
    //        func placeSticker(at result: ARRaycastResult) {
    //
    //            if placedStickers.count >= maxStickers {
    //                print("Maximum number of images reached")
    //                return
    //            }
    //            //let anchorEntity = AnchorEntity(anchor: anchor)
    //            let anchor = ARAnchor(name: "ImageAnchor", transform: result.worldTransform)
    //            let anchorEntity = AnchorEntity(anchor: anchor)
    //            arView.session.add(anchor: anchor)
    //            stickers.append(anchorEntity)
    //            placedStickers.append((anchor.identifier, currentStickerIndex))
    //            placedStickersCount = placedStickers.count
    //
    //            addStickerToScene(anchor: anchor, imageIndex: currentStickerIndex)
    //        }
    
    
    //    private func addStickerToScene(anchor: ARAnchor, imageIndex: Int) {
    //        guard let arView = arView, let material = createMaterialForImage(imageIndex: imageIndex) else { return }
    //        let anchorEntity = AnchorEntity(anchor: anchor)
    //        let mesh = MeshResource.generatePlane(width: 0.2, depth: 0.2)
    //        let imageEntity = ModelEntity(mesh: mesh, materials: [material])
    //        anchorEntity.addChild(imageEntity)
    //        arView.scene.addAnchor(anchorEntity)
    //
    //    }
 
    
    //    func clearAllStickers() {
    //
    //        for (anchorID, _) in placedStickers {
    //            if let anchor = arView.session.currentFrame?.anchors.first(where: { $0.identifier == anchorID }) {
    //                arView.session.remove(anchor: anchor)
    //            }
    //        }
    //        placedStickers.removeAll()
    //        placedStickersCount = 0
    //    }
    
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
    //                self.firestoreManager.saveAnchorEntities(self.stickers, completion: { result in
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
    //    func createAnchor(at transform: simd_float4x4) -> ARAnchor {
    //        let anchor = ARAnchor(transform: transform)
    //        return anchor
    //    }
    //
    //    func restoreAnchors(_ anchorsData: [[String: Any]]) {
    //        for anchorData in anchorsData {
    //            if let transformArray = anchorData["transform"] as? [Float] {
    //                // Reconstruct the transform matrix
    //                let transform = simd_float4x4(
    //                    SIMD4<Float>(transformArray[0], transformArray[1], transformArray[2], transformArray[3]),
    //                    SIMD4<Float>(transformArray[4], transformArray[5], transformArray[6], transformArray[7]),
    //                    SIMD4<Float>(transformArray[8], transformArray[9], transformArray[10], transformArray[11]),
    //                    SIMD4<Float>(transformArray[12], transformArray[13], transformArray[14], transformArray[15])
    //                )
    //
    //                let anchor = ARAnchor(transform: transform)
    //                arView.session.add(anchor: anchor)
    //            }
    //        }
    //    }
    //
    
    
    //    func retreivePlacedStickers() {
    //        AuthManager.shared.signInAnonymously { result in
    //            switch result {
    //            case .success(let user):
    //                print("User signed in anonymously with ID: \(user.uid)")
    //                self.firestoreManager.loadAnchorEntities { result in
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


