import SwiftUI
import RealityKit
import ARKit

class ARViewModel: NSObject, ObservableObject {
    @Published var arView: ARView?
    private var imageAnchor: AnchorEntity?
    private var imageMaterial: SimpleMaterial?
    
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
    
    func setSelectedImage(imageIndex: Int) {
        var material = SimpleMaterial()
        material.color = .init(tint: .white.withAlphaComponent(0.99), texture: .init(try! .load(named: String(format: "image_%04d", imageIndex))))
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
        
        // Remove existing image anchor if any
        if let existingAnchor = imageAnchor {
            arView.scene.removeAnchor(existingAnchor)
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
    }
}

extension ARViewModel: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                let planeMesh = MeshResource.generatePlane(width: planeAnchor.extent.x, depth: planeAnchor.extent.z)
                let material = SimpleMaterial(color: .blue.withAlphaComponent(0.5), isMetallic: false)
                let planeEntity = ModelEntity(mesh: planeMesh, materials: [material])
                
                let anchorEntity = AnchorEntity(anchor: planeAnchor)
                anchorEntity.addChild(planeEntity)
                
                arView?.scene.addAnchor(anchorEntity)
            }
        }
    }
}
