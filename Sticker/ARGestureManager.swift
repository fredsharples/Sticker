import UIKit
import RealityKit
import Combine

class ARGestureManager {
    // MARK: - Properties
    private weak var arView: ARView?
    private weak var selectedEntity: ModelEntity?
    private var cancellables = Set<AnyCancellable>()
    
    // Callback for when an anchor needs to be saved
    var onAnchorSaveNeeded: ((AnchorEntity, ModelEntity) -> Void)?
    
    // MARK: - Initialization
    init(arView: ARView) {
        self.arView = arView
        setupGestures()
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
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let arView = arView else { return }
        
        let location = gesture.location(in: arView)
        
        // Handle entity selection
        if let entity = arView.entity(at: location) as? ModelEntity {
            setSelectedEntity(entity)
        } else {
            setSelectedEntity(nil)
        }
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