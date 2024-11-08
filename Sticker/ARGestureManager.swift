//
//  ARGestureManager.swift
//  Sticker
//
//  Created by Fred Sharples on 11/5/24.
//


import UIKit
import RealityKit
import Combine
import CoreLocation

class ARGestureManager {
    // MARK: - Properties
       private weak var arView: ARView?
       private weak var selectedEntity: ModelEntity?
       private var cancellables = Set<AnyCancellable>()
       
       var currentLocation: CLLocation?
       var imageName: String = ""
       var isReadyForPlacement: Bool = false
       var onAnchorPlacementNeeded: ((float4x4, CLLocation, String) -> Void)?
    
    // Callback for when an anchor needs to be saved
    var onAnchorSaveNeeded: ((AnchorEntity, ModelEntity) -> Void)?
    
    // MARK: - Initialization
    init(arView: ARView) {
        self.arView = arView
        setupGestures()
    }

    
    func updateState(location: CLLocation?, imageName: String, isReady: Bool) {
           self.currentLocation = location
           self.imageName = imageName
           self.isReadyForPlacement = isReady
       }
    
    // MARK: - Gesture Setup
    private func setupGestures() {
        guard let arView = arView else { return }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        
        arView.addGestureRecognizer(tapGesture)
        arView.addGestureRecognizer(panGesture)
        arView.addGestureRecognizer(rotationGesture)
        arView.addGestureRecognizer(pinchGesture)
    }
    
    // MARK: - Public Methods
    func setSelectedEntity(_ entity: ModelEntity?) {
        self.selectedEntity = entity
    }
    
    // MARK: - Gesture Handlers
    // MARK: - Gesture Handlers
        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = arView else { return }
            
            let location = gesture.location(in: arView)
            
            // Handle entity selection
            if let entity = arView.entity(at: location) as? ModelEntity {
                setSelectedEntity(entity)
                return
            }
            
            // Handle sticker placement
            if isReadyForPlacement,
               let currentLocation = currentLocation {
                let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
                
                if let firstResult = results.first {
                    onAnchorPlacementNeeded?(firstResult.worldTransform, currentLocation, imageName)
                }
            }
            
            setSelectedEntity(nil)
        }
        
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let selectedEntity = selectedEntity else { return }
        
        switch gesture.state {
        case .changed:
            let translation = gesture.translation(in: arView)
            let deltaX = Float(translation.x) * 0.001
            let deltaY = Float(-translation.y) * 0.001
            
            selectedEntity.position += SIMD3<Float>(deltaX, deltaY, 0)
            gesture.setTranslation(.zero, in: arView)
            
        case .ended:
            if let anchorEntity = selectedEntity.anchor as? AnchorEntity {
                onAnchorSaveNeeded?(anchorEntity, selectedEntity)
            }
            
        default:
            break
        }
    }
    
    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let selectedEntity = selectedEntity else { return }
        
        switch gesture.state {
        case .changed:
            let rotation = Float(gesture.rotation)
            selectedEntity.orientation = simd_quatf(angle: rotation, axis: SIMD3(0, 0, 1))
            gesture.rotation = 0
            
        case .ended:
            if let anchorEntity = selectedEntity.anchor as? AnchorEntity {
                onAnchorSaveNeeded?(anchorEntity, selectedEntity)
            }
            
        default:
            break
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let selectedEntity = selectedEntity else { return }
        
        switch gesture.state {
        case .changed:
            let scale = Float(gesture.scale)
            selectedEntity.scale *= scale
            gesture.scale = 1
            
        case .ended:
            if let anchorEntity = selectedEntity.anchor as? AnchorEntity {
                onAnchorSaveNeeded?(anchorEntity, selectedEntity)
            }
            
        default:
            break
        }
    }
    
    // MARK: - Cleanup
    func cleanup() {
        cancellables.removeAll()
    }
}
