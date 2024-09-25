//
//  ARViewModel.swift
//  Sticker
//
//  Created by Fred Sharples on 9/25/24.
//

import SwiftUI
import RealityKit
import ARKit

class ARViewModel: NSObject, ObservableObject {
    @Published var arView: ARView?
    
    override init() {
        super.init()
        setupARView()
    }
    
    func setupARView() {
        let arView = ARView(frame: .zero)
        self.arView = arView
        arView.session.delegate = self
    }
    
    func startARSession() {
        guard let arView = arView else { return }
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        
        // Enable camera tracking
        config.environmentTexturing = .automatic
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        arView.session.run(config, options: [.removeExistingAnchors, .resetTracking])
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
