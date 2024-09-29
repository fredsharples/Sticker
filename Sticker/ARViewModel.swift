import SwiftUI
import RealityKit
import ARKit

class ARViewModel: NSObject, ObservableObject {
    @Published var arView: ARView?
    private var imageAnchor: AnchorEntity?
    private var imageMaterial: UnlitMaterial?
    
    private var placedStickers: [(UUID, Int)] = []
    
    @Published var placedStickersCount: Int = 0
    private var stickers: [AnchorEntity] = []
    private var currentStickerIndex: Int = 1
    private let maxStickers = 100
    
    
    override init() {
        super.init()
        setupARView()
    }
    
    func setupARView() {
        let arView = ARView(frame: .zero)
        self.arView = arView
        arView.session.delegate = self

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
    }
    
    func startARSession() {
        guard let arView = arView else { return }
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        arView.session.run(config, options: [.removeExistingAnchors, .resetTracking])
        restorePlacedStickers()
    }
    
    func setSelectedImage(imageIndex: Int) {
        currentStickerIndex = imageIndex
        imageMaterial = createMaterialForImage(imageIndex: imageIndex);
    }
    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let arView = arView else { return }
        let location = gesture.location(in: arView)
        if let result = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any).first {
            placeSticker(at: result)
        }
    }
    
    private func createMaterialForImage(imageIndex: Int) -> UnlitMaterial? {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor.white.withAlphaComponent(0.99), texture: .init(try! .load(named: String(format: "image_%04d", imageIndex))))
        material.tintColor = UIColor.white.withAlphaComponent(0.99)//F# despite being deprecated this actually honors the alpha where the above does not
        return material
    }
    
    func placeSticker(at result: ARRaycastResult) {
        guard let arView = arView else { return }
        
        if placedStickers.count >= maxStickers {
            print("Maximum number of images reached")
            return
        }
        
        let anchor = ARAnchor(name: "ImageAnchor", transform: result.worldTransform)
        arView.session.add(anchor: anchor)
        
        placedStickers.append((anchor.identifier, currentStickerIndex))
        placedStickersCount = placedStickers.count
        
        addStickerToScene(anchor: anchor, imageIndex: currentStickerIndex)
    }
    
    
    private func addStickerToScene(anchor: ARAnchor, imageIndex: Int) {
        guard let arView = arView, let material = createMaterialForImage(imageIndex: imageIndex) else { return }
        let anchorEntity = AnchorEntity(anchor: anchor)
        let mesh = MeshResource.generatePlane(width: 0.2, depth: 0.2)
        let imageEntity = ModelEntity(mesh: mesh, materials: [material])
        anchorEntity.addChild(imageEntity)
        arView.scene.addAnchor(anchorEntity)
    }
    
    func clearAllStickers() {
        guard let arView = arView else { return }
        for (anchorID, _) in placedStickers {
            if let anchor = arView.session.currentFrame?.anchors.first(where: { $0.identifier == anchorID }) {
                arView.session.remove(anchor: anchor)
            }
        }
        placedStickers.removeAll()
        placedStickersCount = 0
    }
    
    func restorePlacedStickers() {
        guard let arView = arView else { return }
        
        for (anchorID, imageIndex) in placedStickers{
            if let anchor = arView.session.currentFrame?.anchors.first(where: { $0.identifier == anchorID }) {
                addStickerToScene(anchor: anchor, imageIndex: imageIndex)
            }
        }
    }
}

extension ARViewModel: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if anchor is ARPlaneAnchor {
                // A plane has been detected
                print("New plane detected")
                
                if let imageAnchor = placedStickers.first(where: { $0.0 == anchor.identifier }) {
                    addStickerToScene(anchor: anchor, imageIndex: imageAnchor.1)
                }
            }
        }
    }
}
