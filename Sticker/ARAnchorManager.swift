import RealityKit
import ARKit
import CoreLocation

class ARAnchorManager {
    // MARK: - Type Definitions
    
    private struct PlaneConfidence {
        let area: Float
        let orientation: Float
        let stability: Int
        let timeSeen: TimeInterval
        
        var score: Float {
            let areaScore = min(area / 0.3, 1.0) // Reduced from 0.5
            let stabilityScore = Float(min(stability, 10)) / 10.0
            let timeScore = Float(min(timeSeen, 3.0) / 3.0)
            return (areaScore * 0.4 + orientation * 0.3 + stabilityScore * 0.2 + timeScore * 0.1)
        }
    }
    private struct AnchorPersistenceData {
        let anchorData: AnchorData
        let lastAttempt: Date
        var attempts: Int
        var bestConfidence: Float
    }
    enum ScanningState {
        case initializing
        case scanning(progress: Float)
        case ready
        case insufficientFeatures
    }
    
    enum ScanningStrategy {
        case standard
        case lidar
        
        var minimumPlaneArea: Float {
            switch self {
            case .standard:
                return 0.3 // square meters for standard scanning
            case .lidar:
                return 0.2 // can be more precise with LiDAR
            }
        }
        
        var requiredPlaneCoverage: Float {
            switch self {
            case .standard:
                return 0.6
            case .lidar:
                return 0.5 // Need less coverage with LiDAR's accuracy
            }
        }
        
        var minimumPlanesForMapping: Int {
            switch self {
            case .standard:
                return 2
            case .lidar:
                return 1 // LiDAR can work with fewer planes
            }
        }
    }
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
        //static let discoveryRange: Double = 5.0 // meters
    }
    
    // MARK: - Properties
    // Core Dependencies
    private weak var arView: ARView?
    private let firebaseManager: FirebaseManager
    
    // Tracking State
    private var detectedPlanes: [ARPlaneAnchor: Float] = [:]
    private var isEnvironmentMapped: Bool = false
    private var isTrackingReady: Bool = false
    private var hasLiDAR: Bool = false
    private var scanningStrategy: ScanningStrategy = .standard
    
    private var planeConfidenceMap: [ARPlaneAnchor: PlaneConfidence] = [:]
    private var persistenceQueue: [AnchorPersistenceData] = []
    private let maxPlacementAttempts = 5
    private let retryInterval: TimeInterval = 2.0
    private let persistenceScheduler = DispatchQueue(label: "com.ar.persistence", qos: .utility)
    private var persistenceTimer: DispatchSourceTimer?
    
    private var lastPlaneUpdate: [ARPlaneAnchor: Date] = [:]
    
    private let viewingAngleThreshold: Float = .pi / 3  // 60 degrees
    private let placementConfidenceThreshold: Float = 0.7
    
    // Anchor Management
    private var anchorEntities: [AnchorEntity] = []
    private var loadedAnchorIds: Set<String> = []
    private var pendingAnchors: [AnchorData] = []
    private var currentImageName: String = ""
    
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
    
    func setScanningStrategy(_ strategy: ScanningStrategy) {
        self.scanningStrategy = strategy
        evaluateEnvironmentMapping()
    }
    
    func addPlaneAnchor() {
        evaluateEnvironmentMapping()
    }
    
    private func queueAnchorForPersistence(_ anchorData: AnchorData) {
        let persistenceData = AnchorPersistenceData(
            anchorData: anchorData,
            lastAttempt: Date(),
            attempts: 0,
            bestConfidence: 0.0
        )
        persistenceQueue.append(persistenceData)
        startPersistenceTimer()
    }
    
    private func startPersistenceTimer() {
        persistenceTimer?.cancel()
        
        let timer = DispatchSource.makeTimerSource(queue: persistenceScheduler)
        timer.schedule(deadline: .now() + retryInterval, repeating: retryInterval)
        timer.setEventHandler(handler: { [weak self] in
            self?.processPersistenceQueue()
        })
        timer.resume()
        
        persistenceTimer = timer
    }

    private func processPersistenceQueue() {
        guard !persistenceQueue.isEmpty else {
            persistenceTimer?.cancel()
            persistenceTimer = nil
            return
        }
        
        let now = Date()
        let itemsToProcess = persistenceQueue.prefix(3) // Process max 3 items per interval
        
        for item in itemsToProcess {
            guard now.timeIntervalSince(item.lastAttempt) >= retryInterval else { continue }
            attemptPlacement(item)
        }
    }
    
    private func attemptPlacement(_ item: AnchorPersistenceData) {
        let origin = SIMD3<Float>(item.anchorData.transform.columns.3.x,
                                 item.anchorData.transform.columns.3.y,
                                 item.anchorData.transform.columns.3.z)
        
        if let placement = findPlacementUsingRaycasts(near: origin) {
            let confidence = validatePlacement(transform: placement.transform, near: origin)
            if confidence > item.bestConfidence && confidence >= 0.7 {
                DispatchQueue.main.async { [weak self] in
                    var finalTransform = placement.transform
                    self?.preserveOriginalOrientation(&finalTransform, from: item.anchorData.transform)
                    self?.createAndPlaceAnchorEntity(transform: finalTransform, anchorData: item.anchorData)
                }
                persistenceQueue.removeAll { $0.anchorData.id == item.anchorData.id }
            }
        }
    }
    
    
    private func isInFieldOfView(_ position: SIMD3<Float>) -> Bool {
        guard let arView = arView,
              let camera = arView.session.currentFrame?.camera else {
            return false
        }
        
        // Get camera transform as matrix_float4x4
        let cameraTransform = camera.transform
        
        // Extract camera position and forward direction
        let cameraPosition = SIMD3<Float>(cameraTransform.columns.3.x,
                                          cameraTransform.columns.3.y,
                                          cameraTransform.columns.3.z)
        
        // Camera's forward direction is negative z in ARKit
        let cameraForward = -SIMD3<Float>(cameraTransform.columns.2.x,
                                          cameraTransform.columns.2.y,
                                          cameraTransform.columns.2.z)
        
        // Calculate vector to position and normalize it
        let toPosition = position - cameraPosition
        let toPositionNormalized = simd_normalize(toPosition)
        
        // Calculate angle between camera forward and position vector
        let angle = acos(simd_dot(cameraForward, toPositionNormalized))
        
        return angle <= viewingAngleThreshold
    }
    
    
    
    private func findMatchingPlane(for transform: float4x4) -> ARPlaneAnchor? {
        guard let frame = arView?.session.currentFrame else { return nil }
        
        let position = transform.position
        let normal = simd_normalize(SIMD3<Float>(transform.columns.1.x,
                                                 transform.columns.1.y,
                                                 transform.columns.1.z))
        
        return frame.anchors.compactMap({ anchor -> ARPlaneAnchor? in
            return anchor as? ARPlaneAnchor
        }).filter({ (planeAnchor: ARPlaneAnchor) -> Bool in
            // Get plane's normal vector (Y-axis of the transform)
            let planeNormal = simd_normalize(SIMD3<Float>(
                planeAnchor.transform.columns.1.x,
                planeAnchor.transform.columns.1.y,
                planeAnchor.transform.columns.1.z
            ))
            
            // Check if position is near the plane
            let planePosition = SIMD3<Float>(
                planeAnchor.transform.columns.3.x,
                planeAnchor.transform.columns.3.y,
                planeAnchor.transform.columns.3.z
            )
            
            let planeToPoint = position - planePosition
            let distanceToPlane = abs(simd_dot(planeToPoint, planeNormal))
            
            // Check if normals are similar (allowing for some tolerance)
            let normalAlignment = abs(simd_dot(normal, planeNormal))
            
            return distanceToPlane < 0.1 && normalAlignment > 0.9
        }).first
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
    
    func reset() {
        print("🔄 Resetting ARAnchorManager state...")
        
        // Reset all tracking state
        detectedPlanes.removeAll()
        isEnvironmentMapped = false
        isTrackingReady = false
        
        // Clear anchor tracking
        loadedAnchorIds.removeAll()
        pendingAnchors.removeAll()
        
        // Remove any existing anchors from the scene
        anchorEntities.forEach { anchor in
            arView?.scene.removeAnchor(anchor)
        }
        anchorEntities.removeAll()
        
        // Reset scanning state
        onScanningStateChanged?(.initializing)
        
        print("✅ ARAnchorManager reset complete")
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
        
        if planeCount >= strategy.minimumPlanesForMapping &&
            (totalArea >= strategy.requiredPlaneCoverage || hasLiDAR) {
            isEnvironmentMapped = true
            //print("✅ Environment mapping complete")
            onScanningStateChanged?(.ready)
        } else {
            let progress = hasLiDAR ?
                min(1.0, Float(planeCount) / Float(strategy.minimumPlanesForMapping)) :
                min(1.0, totalArea / strategy.requiredPlaneCoverage)
            
            if planeCount == 0 {
                onScanningStateChanged?(.insufficientFeatures)
            } else {
                onScanningStateChanged?(.scanning(progress: progress))
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
           // print("📏 Anchor distance: \(distance)m, within range: \(distance <= Constants.discoveryRange)")
            return distance <= ARConstants.discoveryRange
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
    
    /// Places an anchor from saved data, handling both immediate placement and queueing
    /// - Parameter anchorData: The saved anchor data to place
    private func placeSavedAnchor(_ anchorData: AnchorData) {
        if !isEnvironmentMapped {
            queueAnchorForPersistence(anchorData)
            return
        }
        
        let origin = SIMD3<Float>(anchorData.transform.columns.3.x,
                                  anchorData.transform.columns.3.y,
                                  anchorData.transform.columns.3.z)
        
        if let placement = findPlacementUsingRaycasts(near: origin) {
            let confidence = validatePlacement(transform: placement.transform, near: origin)
            if confidence >= 0.7 {
                var finalTransform = placement.transform
                preserveOriginalOrientation(&finalTransform, from: anchorData.transform)
                createAndPlaceAnchorEntity(transform: finalTransform, anchorData: anchorData)
            } else {
                queueAnchorForPersistence(anchorData)
            }
        } else {
            queueAnchorForPersistence(anchorData)
        }
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
        
        // Use new position but maintain original height if within bounds
        adjusted.columns.3 = new.columns.3
        let heightDifference = abs(adjusted.columns.3.y - original.columns.3.y)
        if heightDifference <= 0.3 { // 30cm threshold
            adjusted.columns.3.y = original.columns.3.y
        }
        
        return adjusted
    }
    
    private func findPlacementUsingSavedGeometry(planeGeometry: PlaneGeometry, near position: SIMD3<Float>) -> (transform: float4x4, confidence: Float)? {
        guard let frame = arView?.session.currentFrame else { return nil }
        
        // Look for detected planes that match our saved geometry
        let detectedPlanes = frame.anchors.compactMap { $0 as? ARPlaneAnchor }
        
        for plane in detectedPlanes {
            // Get plane normal
            let planeNormal = SIMD3<Float>(plane.transform.columns.1.x,
                                          plane.transform.columns.1.y,
                                          plane.transform.columns.1.z)
            
            // Check if normals align (allowing for some tolerance)
            let normalAlignment = abs(simd_dot(planeNormal, planeGeometry.normal))
            if normalAlignment > 0.95 { // 95% similarity threshold
                
                // Check if the plane size is similar
                let sizeDifference = abs(simd_length(plane.extent - planeGeometry.extent))
                let sizeConfidence = max(0, 1 - (sizeDifference / simd_length(planeGeometry.extent)))
                
                if sizeConfidence > 0.7 { // 70% size similarity threshold
                    // Create transform at the nearest point on this plane
                    var transform = matrix_identity_float4x4
                    transform.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1)
                    
                    // Calculate confidence based on normal alignment and size similarity
                    let confidence = (normalAlignment + sizeConfidence) / 2.0
                    
                    return (transform, confidence)
                }
            }
        }
        
        return nil
    }
    private func preserveOriginalOrientation(_ transform: inout float4x4, from original: float4x4) {
        let originalRotation = simd_quatf(original)
        let rotMatrix = rotationMatrix(from: originalRotation)
        
        transform.columns.0 = SIMD4<Float>(rotMatrix.columns.0.x, rotMatrix.columns.0.y, rotMatrix.columns.0.z, 0)
        transform.columns.1 = SIMD4<Float>(rotMatrix.columns.1.x, rotMatrix.columns.1.y, rotMatrix.columns.1.z, 0)
        transform.columns.2 = SIMD4<Float>(rotMatrix.columns.2.x, rotMatrix.columns.2.y, rotMatrix.columns.2.z, 0)
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
    
    
    private func findPlacementUsingRaycasts(near position: SIMD3<Float>) -> (transform: float4x4, confidence: Float)? {
        let searchDirections: [(direction: SIMD3<Float>, weight: Float)] = [
            (SIMD3(0, -1, 0), 1.0),           // Straight down
            (SIMD3(0, -0.9063, 0.4226), 0.8), // 25° forward
            (SIMD3(0, -0.9063, -0.4226), 0.8),// 25° back
            (SIMD3(0.4226, -0.9063, 0), 0.8), // 25° right
            (SIMD3(-0.4226, -0.9063, 0), 0.8),// 25° left
            (SIMD3(0, -0.7071, 0.7071), 0.6), // 45° forward
            (SIMD3(0, -0.7071, -0.7071), 0.6),// 45° back
            (SIMD3(0.7071, -0.7071, 0), 0.6), // 45° right
            (SIMD3(-0.7071, -0.7071, 0), 0.6) // 45° left
        ]

        var bestTransform: float4x4?
        var bestConfidence: Float = 0.0

        for (direction, weight) in searchDirections {
            let starts = [
                position + SIMD3<Float>(0, 0.3, 0),     // Above
                position,                                // Center
                position - SIMD3<Float>(0, 0.3, 0)      // Below
            ]

            for start in starts {
                let query = ARRaycastQuery(
                    origin: start,
                    direction: direction,
                    allowing: .estimatedPlane,
                    alignment: .any
                )

                if let result = arView?.session.raycast(query).first {
                    let distance = simd_distance(result.worldTransform.position, position)
                    let distanceConfidence = 1.0 - (distance / Constants.maxDistance)
                    let confidence = distanceConfidence * weight

                    if confidence > bestConfidence {
                        bestConfidence = confidence
                        bestTransform = result.worldTransform
                    }
                }
            }
        }

        return bestTransform.map { ($0, bestConfidence) }
    }
    
    private func validatePlacement(transform: float4x4, near targetPosition: SIMD3<Float>) -> Float {
        let position = transform.position
        let distance = simd_distance(position, targetPosition)
        
        // Check if too far from target
        if distance > Constants.maxDistance { return 0.0 }
        
        // Check height difference
        let heightDiff = abs(position.y - targetPosition.y)
        if heightDiff > 0.5 { return 0.0 }
        
        // Calculate base confidence
        let distanceConfidence = 1.0 - (distance / Constants.maxDistance)
        let heightConfidence = 1.0 - (heightDiff / 0.5)
        
        return (distanceConfidence * 0.7 + heightConfidence * 0.3)
    }
    
    func updatePlaneAnchor(_ planeAnchor: ARPlaneAnchor) {
        let now = Date()
        let area = planeAnchor.planeExtent.width * planeAnchor.planeExtent.height
        let normal = SIMD3<Float>(planeAnchor.transform.columns.1.x,
                                 planeAnchor.transform.columns.1.y,
                                 planeAnchor.transform.columns.1.z)
        let orientation = abs(simd_dot(normal, SIMD3<Float>(0, 1, 0)))
        
        if let lastUpdate = lastPlaneUpdate[planeAnchor] {
            let existing = planeConfidenceMap[planeAnchor]
            let stability = (existing?.stability ?? 0) + 1
            let timeSeen = now.timeIntervalSince(lastUpdate)
            
            planeConfidenceMap[planeAnchor] = PlaneConfidence(
                area: area,
                orientation: orientation,
                stability: stability,
                timeSeen: timeSeen
            )
        } else {
            planeConfidenceMap[planeAnchor] = PlaneConfidence(
                area: area,
                orientation: orientation,
                stability: 1,
                timeSeen: 0
            )
        }
        
        lastPlaneUpdate[planeAnchor] = now
        detectedPlanes[planeAnchor] = area
        evaluateEnvironmentMapping()
    }
 
    func removePlaneAnchor(_ planeAnchor: ARPlaneAnchor) {
        print("🗑️ Removing plane anchor: \(planeAnchor.identifier)")
        detectedPlanes.removeValue(forKey: planeAnchor)
        evaluateEnvironmentMapping()
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
        
        // Update the line to:
        if let planeAnchor = findMatchingPlane(for: anchorEntity.transform.matrix) {
            let planeGeometry = PlaneGeometry(
                center: SIMD3<Float>(planeAnchor.center.x, planeAnchor.center.y, planeAnchor.center.z),
                extent: planeAnchor.extent,  // This already returns simd_float3
                normal: SIMD3<Float>(planeAnchor.transform.columns.1.x,
                                    planeAnchor.transform.columns.1.y,
                                    planeAnchor.transform.columns.1.z)
            )
            anchorData["planeGeometry"] = planeGeometry.dictionary
        }
        
        print("💾 Saving anchor data to Firebase")
        firebaseManager.saveAnchor(anchorData: anchorData)
    }
}

enum ScanningStrategy {
    case standard
    case lidar
}

// MARK: - SIMD Extensions
private extension matrix_float4x4 {
    var position: SIMD3<Float> {
        return SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}

private extension SIMD4<Float> {
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}


