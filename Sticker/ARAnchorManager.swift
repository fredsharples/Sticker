import RealityKit
import ARKit
import CoreLocation

class ARAnchorManager {
    // MARK: - Types
    enum ScanningState {
        case initializing
        case scanning(progress: Float)
        case ready
        case insufficientFeatures
    }
    
    private enum ScanningStrategy {
        case standard
        case lidar
        
        var minimumPlaneArea: Float {
            switch self {
            case .standard:
                return 0.5 // square meters for standard scanning
            case .lidar:
                return 0.2 // can be more precise with LiDAR
            }
        }
        
        var requiredPlaneCoverage: Float {
            switch self {
            case .standard:
                return 1.0
            case .lidar:
                return 0.5 // Need less coverage with LiDAR's accuracy
            }
        }
        
        var minimumPlanesForMapping: Int {
            switch self {
            case .standard:
                return 3
            case .lidar:
                return 1 // LiDAR can work with fewer planes
            }
        }
    }
    
    // MARK: - Properties
    private weak var arView: ARView?
    private let firebaseManager: FirebaseManager
    private var anchorEntities: [AnchorEntity] = []
    private var loadedAnchorIds: Set<String> = []

    // Tracking properties
    private var detectedPlanes: [ARPlaneAnchor: Float] = [:] // Plane to area mapping
    private var isEnvironmentMapped: Bool = false
    private var isTrackingReady: Bool = false
    private var pendingAnchors: [AnchorData] = []
    private var currentImageName: String = ""
    private var hasLiDAR: Bool = false
    private var scanningStrategy: ScanningStrategy = .standard
    
    // MARK: - Constants
    private enum Constants {
        static let stickerSize: SIMD2<Float> = SIMD2(0.2, 0.2)
        static let minDistance: Float = 0.2
        static let maxDistance: Float = 3.0
        static let environmentLightingWeight: Float = 0.5
        static let roughnessValue: Float = 0.9
        static let blendingValue: Float = 0.9
        static let clearcoatValue: Float = 0.9
        static let clearcoatRoughnessValue: Float = 0.9
        static let discoveryRange: Double = 20.0 // meters
    }
    
    // MARK: - Callbacks
    var onAnchorLoadingStateChanged: ((Bool) -> Void)?
    var onAnchorPlaced: ((AnchorEntity) -> Void)?
    var onError: ((Error) -> Void)?
    var onScanningStateChanged: ((ScanningState) -> Void)?
    
    // MARK: - Initialization
    init(arView: ARView, firebaseManager: FirebaseManager) {
        self.arView = arView
        self.firebaseManager = firebaseManager
        
        // Check for LiDAR availability
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            hasLiDAR = true
            scanningStrategy = .lidar
            configureLiDAR()
        }
    }
    
    // MARK: - Public Methods
    func setTrackingReady(_ isReady: Bool) {
        isTrackingReady = isReady
        if isReady {
            processPendingAnchors()
        }
    }
    
    func addPlaneAnchor() {
        evaluateEnvironmentMapping()
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
                   let nearbyAnchors = self.filterNearbyAnchors(anchors, at: location)
                   
                   // Filter out already loaded anchors
                   let newAnchors = nearbyAnchors.filter { anchor in
                       !self.loadedAnchorIds.contains(anchor.id)
                   }
                   
                   if !newAnchors.isEmpty {
                       if self.isEnvironmentMapped {
                           print("🎯 Environment mapped, placing \(newAnchors.count) new anchors")
                           self.placeLoadedAnchors(newAnchors)
                       } else {
                           print("⏳ Environment not mapped, queuing \(newAnchors.count) new anchors")
                           self.pendingAnchors = newAnchors
                       }
                   } else {
                       print("ℹ️ No new anchors to load")
                   }
                   
               case .failure(let error):
                   print("❌ Failed to load anchors: \(error)")
                   self.onError?(error)
               }
               
               self.onAnchorLoadingStateChanged?(false)
           }
       }
    
    func placeNewSticker(at worldTransform: float4x4, location: CLLocation, imageName: String) {
        self.currentImageName = imageName
        
        let anchorEntity = AnchorEntity()
        anchorEntity.name = imageName
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
    
    // Update clearAnchors method
        func clearAnchors() {
            anchorEntities.forEach { anchor in
                arView?.scene.removeAnchor(anchor)
            }
            anchorEntities.removeAll()
            loadedAnchorIds.removeAll()  // Clear the tracked IDs
            print("🧹 Cleared all anchors and tracking data")
        }
    
    // Add method to clear specific anchors
        func clearAnchor(id: String) {
            if let index = anchorEntities.firstIndex(where: { $0.name == id }) {
                let anchor = anchorEntities[index]
                arView?.scene.removeAnchor(anchor)
                anchorEntities.remove(at: index)
                loadedAnchorIds.remove(id)
                print("🗑️ Removed anchor: \(id)")
            }
        }
    
    // MARK: - Private Methods
    private func configureLiDAR() {
            guard let arView = arView else { return }
            
            let configuration = ARWorldTrackingConfiguration()
            
            // Explicitly enable plane detection
            configuration.planeDetection = [.horizontal, .vertical]
            
            // For LiDAR-equipped devices
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                configuration.sceneReconstruction = .mesh
                
                if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
                    configuration.sceneReconstruction = .meshWithClassification
                }
            }
            
            // Print configuration details
            print("🔧 AR Configuration:")
            print("- Plane Detection: \(configuration.planeDetection.rawValue)")
            print("- Scene Reconstruction: \(configuration.sceneReconstruction.rawValue)")
            
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            print("🚀 Started AR session with configuration")
        }
    
    private func evaluateEnvironmentMapping() {
        let strategy = scanningStrategy
        let totalArea = detectedPlanes.values.reduce(0, +)
        let planeCount = detectedPlanes.count
        
        print("📊 Evaluating environment - Planes: \(planeCount), Total Area: \(totalArea)m²")
        
        if planeCount >= strategy.minimumPlanesForMapping &&
           (totalArea >= strategy.requiredPlaneCoverage || hasLiDAR) {
            if !isEnvironmentMapped {
                isEnvironmentMapped = true
                setTrackingReady(true)
                print("✅ Environment mapping complete")
                onScanningStateChanged?(.ready)
                processPendingAnchors()
            }
        } else {
            let progress = hasLiDAR ?
                min(1.0, Float(planeCount) / Float(strategy.minimumPlanesForMapping)) :
                min(1.0, totalArea / strategy.requiredPlaneCoverage)
            print("🔄 Scanning progress: \(Int(progress * 100))%")
            onScanningStateChanged?(.scanning(progress: progress))
            
            if planeCount == 0 {
                onScanningStateChanged?(.insufficientFeatures)
            }
        }
    }
    
    private func filterNearbyAnchors(_ anchors: [AnchorData], at location: CLLocation) -> [AnchorData] {
        anchors.filter { anchorData in
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
            print("📏 Anchor distance: \(distance)m, within range: \(distance <= Constants.discoveryRange)")
            return distance <= Constants.discoveryRange
        }
    }
    
    private func processPendingAnchors() {
        guard !pendingAnchors.isEmpty else { return }
        print("⏳ Processing \(pendingAnchors.count) pending anchors")
        
        let anchorsToProcess = pendingAnchors
        pendingAnchors.removeAll()
        
        for anchorData in anchorsToProcess {
            placeSavedAnchor(anchorData)
        }
    }
    
    private func placeLoadedAnchors(_ anchors: [AnchorData]) {
        print("🎯 Placing \(anchors.count) anchors")
        for anchorData in anchors {
            placeSavedAnchor(anchorData)
        }
    }
    
    private func placeSavedAnchor(_ anchorData: AnchorData) {
            guard isEnvironmentMapped else {
                pendingAnchors.append(anchorData)
                return
            }
            
            let origin = anchorData.transform.position
            var bestPlacement: (transform: float4x4, confidence: Float)?
            
            if hasLiDAR {
                if let meshAnchor = findNearestMeshAnchor(to: origin) {
                    bestPlacement = findOptimalPlacementOnMesh(meshAnchor: meshAnchor, near: origin)
                }
            }
            
            if bestPlacement == nil {
                bestPlacement = findPlacementUsingRaycasts(near: origin)
            }
            
            if let placement = bestPlacement {
                // Create final transform using original orientation
                var finalTransform = placement.transform
                
                // Extract original rotation
                let originalRotation = simd_quatf(anchorData.transform)
                let rotMatrix = rotationMatrix(from: originalRotation)
                
                // Keep rotation columns from original transform
                finalTransform.columns.0 = SIMD4<Float>(rotMatrix.columns.0.x, rotMatrix.columns.0.y, rotMatrix.columns.0.z, 0)
                finalTransform.columns.1 = SIMD4<Float>(rotMatrix.columns.1.x, rotMatrix.columns.1.y, rotMatrix.columns.1.z, 0)
                finalTransform.columns.2 = SIMD4<Float>(rotMatrix.columns.2.x, rotMatrix.columns.2.y, rotMatrix.columns.2.z, 0)
                
                // Use new position
                finalTransform.columns.3 = placement.transform.columns.3
                
                // Add small offset to prevent z-fighting
                finalTransform.columns.3.y += 0.001
                
                createAndPlaceAnchorEntity(transform: finalTransform, anchorData: anchorData)
            } else {
                print("⚠️ No suitable surface found, queueing anchor for retry")
                pendingAnchors.append(anchorData)
            }
        }
    
    
    private func rotationMatrix(from quaternion: simd_quatf) -> matrix_float4x4 {
           // Extract components from quaternion.vector (which is a SIMD4<Float>)
           let x = quaternion.vector.x
           let y = quaternion.vector.y
           let z = quaternion.vector.z
           let w = quaternion.vector.w
           
           // Calculate common products once
           let x2 = x * x
           let y2 = y * y
           let z2 = z * z
           let xy = x * y
           let xz = x * z
           let yz = y * z
           let wx = w * x
           let wy = w * y
           let wz = w * z
           
           // Create column vectors
           let column0 = SIMD4<Float>(
               1.0 - 2.0 * (y2 + z2),
               2.0 * (xy + wz),
               2.0 * (xz - wy),
               0.0
           )
           
           let column1 = SIMD4<Float>(
               2.0 * (xy - wz),
               1.0 - 2.0 * (x2 + z2),
               2.0 * (yz + wx),
               0.0
           )
           
           let column2 = SIMD4<Float>(
               2.0 * (xz + wy),
               2.0 * (yz - wx),
               1.0 - 2.0 * (x2 + y2),
               0.0
           )
           
           let column3 = SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
           
           // Create matrix from columns
           return matrix_float4x4(columns: (column0, column1, column2, column3))
       }
    
    
    private func adjustTransformForPlacement(original: float4x4, new: float4x4, confidence: Float) -> float4x4 {
           var adjusted = matrix_identity_float4x4
           
           // Extract and use original rotation
           let originalRotation = simd_quatf(original)
           let rotMatrix = rotationMatrix(from: originalRotation)
           
           // Apply rotation
           adjusted.columns.0 = SIMD4<Float>(rotMatrix.columns.0.x, rotMatrix.columns.0.y, rotMatrix.columns.0.z, 0)
           adjusted.columns.1 = SIMD4<Float>(rotMatrix.columns.1.x, rotMatrix.columns.1.y, rotMatrix.columns.1.z, 0)
           adjusted.columns.2 = SIMD4<Float>(rotMatrix.columns.2.x, rotMatrix.columns.2.y, rotMatrix.columns.2.z, 0)
           
           // Use new position
           adjusted.columns.3 = new.columns.3
           adjusted.columns.3.y += 0.001
           
           return adjusted
       }
    
    func updatePlaneAnchor(_ planeAnchor: ARPlaneAnchor) {
            print("📐 Updating plane anchor: \(planeAnchor.identifier)")
            detectedPlanes[planeAnchor] = planeAnchor.extent.x * planeAnchor.extent.z
            evaluateEnvironmentMapping()
        }
    
    func removePlaneAnchor(_ planeAnchor: ARPlaneAnchor) {
         print("🗑️ Removing plane anchor: \(planeAnchor.identifier)")
         detectedPlanes.removeValue(forKey: planeAnchor)
         evaluateEnvironmentMapping()
     }
    
    
    private func findNearestMeshAnchor(to position: SIMD3<Float>) -> ARMeshAnchor? {
        guard let meshAnchors = arView?.session.currentFrame?.anchors.compactMap({ $0 as? ARMeshAnchor }) else {
            return nil
        }
        
        return meshAnchors.min(by: { anchor1, anchor2 in
            let distance1 = simd_distance(anchor1.transform.position, position)
            let distance2 = simd_distance(anchor2.transform.position, position)
            return distance1 < distance2
        })
    }
    
    private func findOptimalPlacementOnMesh(meshAnchor: ARMeshAnchor, near position: SIMD3<Float>) -> (transform: float4x4, confidence: Float)? {
            guard let geometry = meshAnchor.geometry as? ARMeshGeometry else { return nil }
            
            let meshLocalPosition = meshAnchor.transform.inverse * float4(position.x, position.y, position.z, 1)
            
            var nearestVertex: SIMD3<Float>?
            var nearestNormal: SIMD3<Float>?
            var minDistance: Float = .infinity
            
            // Get the raw vertex buffer
            let vertices = geometry.vertices.buffer.contents()
            let vertexStride = geometry.vertices.stride
            let vertexCount = geometry.vertices.count
            
            // Get the raw normal buffer
            let normals = geometry.normals.buffer.contents()
            let normalStride = geometry.normals.stride
            
            // Iterate through vertices
            for index in 0..<vertexCount {
                // Get vertex at current index
                let vertexPointer = vertices.advanced(by: index * vertexStride)
                let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
                
                let distance = simd_distance(vertex, meshLocalPosition.xyz)
                
                if distance < minDistance {
                    minDistance = distance
                    nearestVertex = vertex
                    
                    // Get corresponding normal
                    let normalPointer = normals.advanced(by: index * normalStride)
                    nearestNormal = normalPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
                }
            }
            
            guard let vertex = nearestVertex, let normal = nearestNormal else { return nil }
            
            var transform = matrix_identity_float4x4
            transform.columns.3 = float4(vertex.x, vertex.y, vertex.z, 1)
            
            // Calculate confidence (0-1) based on distance
            let confidence = 1.0 - (minDistance / 0.1)
            
            return (meshAnchor.transform * transform, confidence)
        }
    
    private func findPlacementUsingRaycasts(near position: SIMD3<Float>) -> (transform: float4x4, confidence: Float)? {
        let searchDirections: [SIMD3<Float>] = [
            SIMD3(0, -1, 0),
            SIMD3(0, -0.7071, 0.7071),
            SIMD3(0, -0.7071, -0.7071),
            SIMD3(0.7071, -0.7071, 0),
            SIMD3(-0.7071, -0.7071, 0)
        ]
        
        var bestResult: ARRaycastResult?
        var bestConfidence: Float = 0.0
        
        for direction in searchDirections {
            let raycastQuery = ARRaycastQuery(
                origin: position + SIMD3<Float>(0, 0.3, 0),
                direction: direction,
                allowing: .estimatedPlane,
                alignment: .any
            )
            
            if let result = arView?.session.raycast(raycastQuery).first {
                let distance = simd_distance(result.worldTransform.position, position)
                let confidence = 1.0 - (distance / Constants.maxDistance)
                
                if confidence > bestConfidence {
                    bestConfidence = confidence
                    bestResult = result
                }
            }
        }
        
        return bestResult.map { ($0.worldTransform, bestConfidence) }
    }
    
   
    
    private func createAndPlaceAnchorEntity(transform: float4x4, anchorData: AnchorData) {
            guard !loadedAnchorIds.contains(anchorData.id) else {
                print("⚠️ Anchor \(anchorData.id) already loaded, skipping")
                return
            }
            
            let anchorEntity = AnchorEntity(world: transform)
            anchorEntity.name = anchorData.id
            
            if let modelEntity = createModelEntity(img: anchorData.name) {
                // Apply scale if available
                if let scale = anchorData.scale {
                    modelEntity.scale = scale
                }
                
                // Apply orientation if available, otherwise use transform orientation
                if let orientation = anchorData.orientation {
                    modelEntity.orientation = orientation
                }
                
                modelEntity.generateCollisionShapes(recursive: true)
                anchorEntity.addChild(modelEntity)
                arView?.scene.addAnchor(anchorEntity)
                anchorEntities.append(anchorEntity)
                loadedAnchorIds.insert(anchorData.id)
                onAnchorPlaced?(anchorEntity)
                print("✅ Successfully placed anchor entity: \(anchorData.id) with orientation: \(modelEntity.orientation)")
            }
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
                "name": currentImageName,
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "altitude": location.altitude,
                "horizontalAccuracy": location.horizontalAccuracy,
                "verticalAccuracy": location.verticalAccuracy,
                "timestamp": location.timestamp.timeIntervalSince1970
            ]
            
            // Save scale
            anchorData["scale"] = [
                Double(modelEntity.scale.x),
                Double(modelEntity.scale.y),
                Double(modelEntity.scale.z)
            ]
            
            // Save orientation
            anchorData["orientation"] = [
                Double(modelEntity.orientation.vector.x),
                Double(modelEntity.orientation.vector.y),
                Double(modelEntity.orientation.vector.z),
                Double(modelEntity.orientation.vector.w)
            ]
            
            print("💾 Saving anchor data to Firebase")
            firebaseManager.saveAnchor(anchorData: anchorData)
        }
    }

    // MARK: - SIMD Extensions
    private extension simd_float4x4 {
        var position: SIMD3<Float> {
            return SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
        }
    }

    private extension float4 {
        var xyz: SIMD3<Float> {
            return SIMD3<Float>(x, y, z)
        }
    }
