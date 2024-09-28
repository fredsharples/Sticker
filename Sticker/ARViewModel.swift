import SwiftUI
import RealityKit
import ARKit

class ARViewModel: NSObject, ObservableObject {
    @Published var arView: ARView?
    private var imageAnchor: AnchorEntity?
    private var imageMaterial: UnlitMaterial?
    
    @Published var placedStickersCount: Int = 0
    private var stickers: [AnchorEntity] = []
    private var currentImageIndex: Int = 1
    private let maxStickers = 100
    
    
    override init() {
        super.init()
        setupARView()
    }
    
    func setupARView() {
        let arView = ARView(frame: .zero)
        self.arView = arView
        arView.session.delegate = self
        
        // Add tap gesture recognizer
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
    }
    
    func changeSelectedImage(imageIndex: Int) {
        currentImageIndex = imageIndex
        setSelectedImage(imageIndex: imageIndex)
    }
    
    func setSelectedImage(imageIndex: Int) {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor.white.withAlphaComponent(0.99), texture: .init(try! .load(named: String(format: "image_%04d", imageIndex))))
        material.tintColor = UIColor.white.withAlphaComponent(0.99)//F# despite being deprecated this actually honors the alpha where the above does not
        imageMaterial = material;
    }
    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let arView = arView else { return }
        
        let location = gesture.location(in: arView)
        
        if let result = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any).first {
            placeImage(at: result)
        }
    }
    
    
    func placeImage(at result: ARRaycastResult) {
        guard let arView = arView, let material = imageMaterial else { return }
        
        if stickers.count >= maxStickers {
                       print("Maximum number of stickers reached")
                       return
                   }
        
        // Create a new anchor at the tap location
        let anchor = AnchorEntity(raycastResult: result)
        
        // Create a plane to display the image
        let mesh = MeshResource.generatePlane(width: 0.2, depth: 0.2)
        let imageEntity = ModelEntity(mesh: mesh, materials: [material])
        
        // Enable double-sided rendering for transparency
        imageEntity.model?.materials = [material, material]
        
        // Add the image entity to the anchor
        anchor.addChild(imageEntity)
        
        // Add the anchor to the scene
        arView.scene.addAnchor(anchor)
        
        // Store the new anchor
        imageAnchor = anchor
        
        // Store the new anchor
                    stickers.append(anchor)
                    placedStickersCount = stickers.count
    }
    
    func clearAllStickers() {
                guard let arView = arView else { return }
                for sticker in stickers {
                    arView.scene.removeAnchor(sticker)
                }
                stickers.removeAll()
                placedStickersCount = 0
            }
    
}

extension ARViewModel: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if anchor is ARPlaneAnchor {
                // A plane has been detected
                print("New plane detected")
                
                // You can add any non-visual logic here if needed
                // For example, you might want to update some internal state
                // or trigger some other functionality when a new plane is detected
            }
        }
    }
}
