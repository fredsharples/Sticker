import SwiftUI
import RealityKit
import ARKit
import CoreLocation
import CoreMotion
import Combine



// MARK: - ARViewModel
class ARViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var state: ARStickerViewState = .initializing  // Updated type
    @Published private(set) var error: ARStickerError?
    @Published var arView: ARView
    @Published var currentLocation: CLLocation?
    @Published var heading: CLHeading?
    @Published var motionData: CMDeviceMotion?
    @Published var selectedImageIndex: Int = 1
    @Published private(set) var isPlacementEnabled: Bool = false
    @Published private(set) var scanningState: ARAnchorManager.ScanningState = .initializing
    
    // MARK: - Private Properties
    private var gestureManager: ARGestureManager?
    private var anchorManager: ARAnchorManager?
    private let locationManager: ARLocationManager
    private var sessionManager: ARSessionManager?
    private let firebaseManager = FirebaseManager()
    private var cancellables = Set<AnyCancellable>()
    private var anchorEntities: [AnchorEntity] = []
    private var selectedEntity: ModelEntity?
    private var imageName: String = ""
    private let loadingRange: Double = 100 // meters
    
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
    }
    
    // MARK: - Initialization
    override init() {
        arView = ARView(frame: .zero)
        locationManager = ARLocationManager()
        super.init()
        setupBindings()
        setupARView()
        initializeFirebase()
        setLiDAREnabled(true);
        
    }
    
    // MARK: - Setup Methods
    private func setupARView() {
        
        anchorManager = ARAnchorManager(arView: arView, firebaseManager: firebaseManager)
           anchorManager?.onScanningStateChanged = { [weak self] state in
               DispatchQueue.main.async {
                   self?.scanningState = state
                   if case .ready = state {
                       self?.isPlacementEnabled = true
                   } else {
                       self?.isPlacementEnabled = false
                   }
               }
           }
        
        
        if let anchorManager = anchorManager {
                sessionManager = ARSessionManager(arView: arView, anchorManager: anchorManager)
                
                // Observe session state
                sessionManager?.$isSessionReady
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] isReady in
                        if !isReady {
                            self?.isPlacementEnabled = false
                        }
                    }
                    .store(in: &cancellables)
                
                sessionManager?.$sessionError
                    .receive(on: DispatchQueue.main)
                    .compactMap { $0 }
                    .sink { [weak self] error in
                        self?.state = .error(.loadFailed)
                    }
                    .store(in: &cancellables)
            }
        
        sessionManager?.$isSessionReady
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isReady in
                    if !isReady {
                        self?.isPlacementEnabled = false
                    }
                }
                .store(in: &cancellables)
            
            sessionManager?.$sessionError
                .receive(on: DispatchQueue.main)
                .compactMap { $0 }
                .sink { [weak self] error in
                    self?.state = .error(.loadFailed)
                }
                .store(in: &cancellables)
            
            // Setup gesture manager
            gestureManager = ARGestureManager(arView: arView)
            gestureManager?.onAnchorPlacementNeeded = { [weak self] transform, location, imageName in
                self?.anchorManager?.placeNewSticker(
                    at: transform,
                    location: location,
                    imageName: imageName
                )
            }

        gestureManager = ARGestureManager(arView: arView)
        gestureManager?.onAnchorPlacementNeeded = { [weak self] transform, location, imageName in
            self?.anchorManager?.placeNewSticker(
                at: transform,
                location: location,
                imageName: imageName
            )
        }
        
    }
    func setLiDAREnabled(_ enabled: Bool) {
        sessionManager?.setLiDAREnabled(enabled)
        anchorManager?.setScanningStrategy(enabled ? .lidar : .standard)
    }
    
    // Update state when needed
    private func updateGestureManagerState() {
        gestureManager?.updateState(
            location: currentLocation,
            imageName: imageName,
            isReady: state == ARStickerViewState.ready
        )
    }
    
    private func setupBindings() {
        // Update currentLocation when location manager updates
        locationManager.$currentLocation
            .assign(to: \.currentLocation, on: self)
            .store(in: &cancellables)
        
        // Update heading when location manager updates
        locationManager.$heading
            .assign(to: \.heading, on: self)
            .store(in: &cancellables)
        
        // Update motion data when location manager updates
        locationManager.$motionData
            .assign(to: \.motionData, on: self)
            .store(in: &cancellables)
    }
    
    
    
    
    
    
    private func initializeFirebase() {
        state = .loading
        firebaseManager.loginFirebase { [weak self] result in
            switch result {
            case .success(let user):
                print("Logged in as user: \(user.uid)")
                self?.loadSavedAnchors()
                self?.state = .ready
            case .failure(let error):
                print("Failed to log in: \(error.localizedDescription)")
                self?.state = .error(.loadFailed)
            }
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
    
    
    // MARK: - Data Management

    
    
    // MARK: - Public Methods
    func loadSavedAnchors() {
        guard isPlacementEnabled else {
            print("Environment not ready for loading anchors")
            return
        }
        anchorManager?.loadSavedAnchors(at: currentLocation)
    }
    
    
    
    func clearAll() {
        anchorManager?.clearAnchors()
    }
    
    func deleteAllFromFirebase() {
        state = .loading
        firebaseManager.deleteAllAnchors { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                print("All anchors have been deleted from Firebase")
                self.clearAll()
                self.state = .ready
                
            case .failure(let error):
                print("Failed to delete anchors: \(error)")
                self.state = .error(.saveFailed)
            }
        }
    }
    
    // Call updateGestureManagerState when relevant properties change
    // For example, in setSelectedImage:
    func setSelectedImage(imageIndex: Int) {
        selectedImageIndex = imageIndex
        imageName = String(format: "image_%04d", imageIndex)
        updateGestureManagerState()
        print("Selected sticker number: \(selectedImageIndex)")
    }
    
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                print("✨ New plane detected: \(planeAnchor.identifier)")
                anchorManager?.updatePlaneAnchor(planeAnchor)
            }
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                //print("🔄 Plane updated: \(planeAnchor.identifier)")
                anchorManager?.updatePlaneAnchor(planeAnchor)
            }
        }
    }
    
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                print("❌ Plane removed: \(planeAnchor.identifier)")
                anchorManager?.removePlaneAnchor(planeAnchor)
            }
        }
    }

    
    private func updateSelectedEntity(_ entity: ModelEntity?) {
        selectedEntity = entity
        gestureManager?.setSelectedEntity(entity)
    }
    
    // MARK: - Cleanup
    deinit {
        gestureManager?.cleanup()
        locationManager.cleanup()
    }
}

private extension simd_float4x4 {
    var position: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}


// MARK: - Error Types
enum ARStickerError: Error, LocalizedError {
    case locationUnavailable
    case raycastFailed
    case textureLoadFailed
    case anchorCreationFailed
    case saveFailed
    case loadFailed
    
    var errorDescription: String? {
        switch self {
        case .locationUnavailable:
            return "Unable to access location. Please check permissions."
        case .raycastFailed:
            return "Cannot place sticker here. Try a different surface."
        case .textureLoadFailed:
            return "Failed to load sticker image. Please try again."
        case .anchorCreationFailed:
            return "Failed to place sticker. Please try again."
        case .saveFailed:
            return "Failed to save sticker. Please try again."
        case .loadFailed:
            return "Failed to load stickers. Please try again."
        }
    }
}

// MARK: - Sticker State
enum ARStickerViewState: Equatable {
    case initializing
    case ready
    case placing
    case loading
    case error(ARStickerError)
    
    static func == (lhs: ARStickerViewState, rhs: ARStickerViewState) -> Bool {
        switch (lhs, rhs) {
        case (.initializing, .initializing):
            return true
        case (.ready, .ready):
            return true
        case (.placing, .placing):
            return true
        case (.loading, .loading):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

