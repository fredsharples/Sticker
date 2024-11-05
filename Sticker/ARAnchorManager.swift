import RealityKit
import ARKit
import CoreLocation

class ARAnchorManager {
    // MARK: - Properties
    private weak var arView: ARView?
    private let firebaseManager: FirebaseManager
    private var anchorEntities: [AnchorEntity] = []
    private let loadingRange: Double = 100 // meters
    
    // Tracking properties for surface detection
    private var isTrackingReady: Bool = false
    private var detectedPlanes: Int = 0
    private var pendingAnchors: [AnchorData] = []
    private let minimumPlanesForReady = 1
    private var currentImageName: String = ""
    
    // Constants for sticker creation
    private enum Constants {
        static let stickerSize: SIMD2<Float> = SIMD2(0.2, 0.2)
        static let minDistance: Float = 0.2
        static let maxDistance: Float = 3.0
        static let environmentLightingWeight: Float = 0.5
        static let roughnessValue: Float = 0.9
        static let blendingValue: Float = 0.9
        static let clearcoatValue: Float = 0.9
        static let clearcoatRoughnessValue: Float = 0.9
    }
    
    // Callbacks
    var onAnchorLoadingStateChanged: ((Bool) -> Void)?
    var onAnchorPlaced: ((AnchorEntity) -> Void)?
    var onError: ((Error) -> Void)?
    
    // MARK: - Initialization
    init(arView: ARView, firebaseManager: FirebaseManager) {
        self.arView = arView
        self.firebaseManager = firebaseManager
    }
    
    // MARK: - Public Methods
    func setTrackingReady(_ isReady: Bool) {
        isTrackingReady = isReady
        if isReady {
            processPendingAnchors()
        }
    }
    
    func addPlaneAnchor() {
        detectedPlanes += 1
        if detectedPlanes >= minimumPlanesForReady {
            setTrackingReady(true)
        }
    }
    
    func loadSavedAnchors(at location: CLLocation?) {
            guard let location = location else {
                print("🔍 Location not available for loading anchors")
                onError?(ARStickerError.locationUnavailable)
                return
            }
            
            print("🔍 Loading anchors at location: \(location.coordinate)")
            onAnchorLoadingStateChanged?(true)
            
            firebaseManager.loadAnchors { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(let anchors):
                    print("📍 Loaded \(anchors.count) anchors from Firebase")
                    if self.isTrackingReady {
                        print("🎯 AR Tracking ready, placing anchors")
                        self.placeLoadedAnchors(anchors, at: location)
                    } else {
                        print("⏳ AR Tracking not ready, queuing \(anchors.count) anchors")
                        self.pendingAnchors = anchors
                    }
                    
                case .failure(let error):
                    print("❌ Failed to load anchors: \(error)")
                    self.onError?(error)
                }
                
                self.onAnchorLoadingStateChanged?(false)
            }
        }
    
    func placeNewSticker(at worldTransform: float4x4, location: CLLocation, imageName: String) {
            self.currentImageName = imageName  // Store the image name
            
            let anchorEntity = AnchorEntity()
            anchorEntity.name = imageName  // Use image name as anchor name
            anchorEntity.setTransformMatrix(worldTransform, relativeTo: nil)
            
            guard let modelEntity = createModelEntity(img: imageName) else {
                onError?(ARStickerError.textureLoadFailed)
                return
            }
            
            anchorEntity.addChild(modelEntity)
            arView?.scene.addAnchor(anchorEntity)
            anchorEntities.append(anchorEntity)
            
            saveAnchor(anchorEntity: anchorEntity, modelEntity: modelEntity, location: location)
            onAnchorPlaced?(anchorEntity)
        }
    
    func clearAnchors() {
        anchorEntities.forEach { anchor in
            arView?.scene.removeAnchor(anchor)
        }
        anchorEntities.removeAll()
    }
    
    // MARK: - Private Methods
    private func processPendingAnchors() {
        guard !pendingAnchors.isEmpty,
              let location = arView?.session.currentFrame?.camera.transform.position.location else {
            return
        }
        
        placeLoadedAnchors(pendingAnchors, at: location)
        pendingAnchors.removeAll()
    }
    
    private func placeLoadedAnchors(_ anchors: [AnchorData], at location: CLLocation) {
            let nearbyAnchors = anchors.filter { anchorData in
                let anchorLocation = CLLocation(
                    coordinate: CLLocationCoordinate2D(
                        latitude: anchorData.latitude,
                        longitude: anchorData.longitude
                    ),
                    altitude: anchorData.altitude,
                    horizontalAccuracy: anchorData.horizontalAccuracy,
                    verticalAccuracy: anchorData.verticalAccuracy,
                    timestamp: Date(timeIntervalSince1970: anchorData.timestamp)
                )
                let distance = location.distance(from: anchorLocation)
                print("📏 Anchor distance: \(distance)m, within range: \(distance <= loadingRange)")
                return distance <= loadingRange
            }
            
            print("🎯 Found \(nearbyAnchors.count) nearby anchors out of \(anchors.count) total")
            
            for anchorData in nearbyAnchors {
                placeSavedAnchor(anchorData)
            }
        }
    
    private func placeSavedAnchor(_ anchorData: AnchorData) {
            guard isTrackingReady else {
                print("⏳ Tracking not ready, deferring anchor placement")
                return
            }
            
            print("🎯 Placing anchor: \(anchorData.name) at location: (\(anchorData.latitude), \(anchorData.longitude))")
            
            let origin = anchorData.transform.position
            let elevatedOrigin = origin + SIMD3<Float>(0, 0.3, 0)
            
            guard let arView = arView else { return }
            
            let raycastQuery = ARRaycastQuery(
                origin: elevatedOrigin,
                direction: [0, -1, 0],
                allowing: .estimatedPlane,
                alignment: .any
            )
            
            let results = arView.session.raycast(raycastQuery)
            
            if let firstResult = results.first {
                print("✅ Found surface for anchor placement")
                var adjustedTransform = firstResult.worldTransform
                adjustedTransform.columns.3.y += 0.01
                
                let anchorEntity = AnchorEntity(world: adjustedTransform)
                if let modelEntity = createModelEntity(img: anchorData.name) {
                    if let scale = anchorData.scale {
                        modelEntity.scale = scale
                    }
                    if let orientation = anchorData.orientation {
                        modelEntity.orientation = orientation
                    }
                    
                    modelEntity.generateCollisionShapes(recursive: true)
                    anchorEntity.addChild(modelEntity)
                    arView.scene.addAnchor(anchorEntity)
                    anchorEntities.append(anchorEntity)
                    onAnchorPlaced?(anchorEntity)
                    print("✅ Successfully placed anchor")
                } else {
                    print("❌ Failed to create model entity for: \(anchorData.name)")
                }
            } else {
                print("⚠️ No surface found for anchor placement")
            }
        }
    
    private func saveAnchor(anchorEntity: AnchorEntity, modelEntity: ModelEntity, location: CLLocation) {
            let matrix = anchorEntity.transform.matrix
            
            // Break down matrix columns into separate arrays
            let column0 = [
                Double(matrix.columns.0.x),
                Double(matrix.columns.0.y),
                Double(matrix.columns.0.z),
                Double(matrix.columns.0.w)
            ]
            
            let column1 = [
                Double(matrix.columns.1.x),
                Double(matrix.columns.1.y),
                Double(matrix.columns.1.z),
                Double(matrix.columns.1.w)
            ]
            
            let column2 = [
                Double(matrix.columns.2.x),
                Double(matrix.columns.2.y),
                Double(matrix.columns.2.z),
                Double(matrix.columns.2.w)
            ]
            
            let column3 = [
                Double(matrix.columns.3.x),
                Double(matrix.columns.3.y),
                Double(matrix.columns.3.z),
                Double(matrix.columns.3.w)
            ]
            
            // Combine columns
            let transformArray = column0 + column1 + column2 + column3
            
            var anchorData: [String: Any] = [
                "id": anchorEntity.id.description,
                "transform": transformArray,
                "name": currentImageName,  // Use the stored image name
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "altitude": location.altitude,
                "horizontalAccuracy": location.horizontalAccuracy,
                "verticalAccuracy": location.verticalAccuracy,
                "timestamp": location.timestamp.timeIntervalSince1970
            ]
            
            anchorData["scale"] = [
                Double(modelEntity.scale.x),
                Double(modelEntity.scale.y),
                Double(modelEntity.scale.z)
            ]
            
            anchorData["orientation"] = [
                Double(modelEntity.orientation.vector.x),
                Double(modelEntity.orientation.vector.y),
                Double(modelEntity.orientation.vector.z),
                Double(modelEntity.orientation.vector.w)
            ]
            
            firebaseManager.saveAnchor(anchorData: anchorData)
        }
    
    private func createModelEntity(img: String) -> ModelEntity? {
        let mesh = MeshResource.generatePlane(width: Constants.stickerSize.x, depth: Constants.stickerSize.y)
        var material = PhysicallyBasedMaterial()
        
        guard let texture = try? TextureResource.load(named: img) else {
            print("Failed to load texture: \(img)")
            return nil
        }
        
        material.baseColor.texture = PhysicallyBasedMaterial.Texture(texture)
        material.opacityThreshold = 0.5
        material.roughness = .init(floatLiteral: Constants.roughnessValue)
        material.blending = .transparent(opacity: .init(floatLiteral: Constants.blendingValue))
        material.clearcoat = .init(floatLiteral: Constants.clearcoatValue)
        material.clearcoatRoughness = .init(floatLiteral: Constants.clearcoatRoughnessValue)
        
        let modelEntity = ModelEntity(mesh: mesh, materials: [material])
        modelEntity.components.set(EnvironmentLightingConfigurationComponent(
            environmentLightingWeight: Constants.environmentLightingWeight))
        
        modelEntity.generateCollisionShapes(recursive: true)
        return modelEntity
    }
}
// MARK: - SIMD Extensions
private extension simd_float4x4 {
    var position: SIMD3<Float> {
        return SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}

private extension SIMD3<Float> {
    var location: CLLocation? {
        return CLLocation(latitude: Double(x), longitude: Double(z))
    }
}
