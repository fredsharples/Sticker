import Firebase
import FirebaseFirestore
import FirebaseAuth
import RealityKit
import CoreLocation

class FirebaseManager {
    private let db = Firestore.firestore()
    private let stickersCollection = "stickers"
    private var currentUser: User?
    
    // MARK: - Initialization
    init() {
        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] (_, user) in
            self?.currentUser = user
        }
    }
    
    // MARK: - Authentication
    func loginFirebase(completion: @escaping (Result<User, Error>) -> Void) {
        AuthManager.shared.signInAnonymously { result in
            switch result {
            case .success(let user):
                self.currentUser = user
                print("User signed in with persistent ID: \(user.uid)")
                completion(.success(user))
            case .failure(let error):
                print("Error signing in: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Save Anchor
    func saveAnchor(anchorData: [String: Any]) {
        guard let userId = currentUser?.uid else {
            print("Error: No authenticated user")
            return
        }
        
        // Add user ID to anchor data
        var enrichedAnchorData = anchorData
        enrichedAnchorData["userId"] = userId
        enrichedAnchorData["createdAt"] = FieldValue.serverTimestamp()
        
        let idString = anchorData["id"] as! String
        
        // Store in user-specific subcollection
        let userStickersRef = db.collection("users").document(userId)
            .collection(stickersCollection).document(idString)
        
        userStickersRef.setData(enrichedAnchorData) { error in
            if let error = error {
                print("Error saving anchor: \(error.localizedDescription)")
            } else {
                print("Anchor saved successfully for user: \(userId)")
            }
        }
    }
    
    // MARK: - Load Anchors
    func loadAnchors(completion: @escaping (Result<[AnchorData], Error>) -> Void) {
        guard let userId = currentUser?.uid else {
            completion(.failure(NSError(domain: "FirebaseManager",
                                     code: -1,
                                     userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])))
            return
        }
        
        // Get user's stickers
        let userStickersRef = db.collection("users").document(userId)
            .collection(stickersCollection)
        
        userStickersRef.getDocuments { snapshot, error in
            if let error = error {
                print("Error loading anchors: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("No stickers found for user: \(userId)")
                completion(.success([]))
                return
            }
            
            let anchors = documents.compactMap { doc -> AnchorData? in
                let data = doc.data()
                return AnchorData(dictionary: data)
            }
            
            print("Loaded \(anchors.count) stickers for user: \(userId)")
            completion(.success(anchors))
        }
    }
    
    // MARK: - Load Nearby Anchors
    func loadNearbyAnchors(location: CLLocation, radius: Double, completion: @escaping (Result<[AnchorData], Error>) -> Void) {
        // Get all users' public stickers within radius
        let geoQuery = db.collectionGroup(stickersCollection)
            .whereField("isPublic", isEqualTo: true)
        
        geoQuery.getDocuments { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let documents = snapshot?.documents else {
                completion(.success([]))
                return
            }
            
            let anchors = documents.compactMap { doc -> AnchorData? in
                let data = doc.data()
                guard let anchorData = AnchorData(dictionary: data),
                      let anchorLocation = anchorData.location else {
                    return nil
                }
                
                // Filter by distance
                let distance = location.distance(from: anchorLocation)
                return distance <= radius ? anchorData : nil
            }
            
            completion(.success(anchors))
        }
    }
    
    // MARK: - Delete Anchors
    func deleteAllAnchors(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = currentUser?.uid else {
            completion(.failure(NSError(domain: "FirebaseManager",
                                     code: -1,
                                     userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])))
            return
        }
        
        let userStickersRef = db.collection("users").document(userId)
            .collection(stickersCollection)
        
        userStickersRef.getDocuments { (snapshot, error) in
            if let error = error {
                print("Error fetching documents: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let snapshot = snapshot else {
                completion(.success(()))
                return
            }
            
            let batch = self.db.batch()
            
            for document in snapshot.documents {
                batch.deleteDocument(document.reference)
            }
            
            batch.commit { (batchError) in
                if let batchError = batchError {
                    print("Error deleting documents: \(batchError.localizedDescription)")
                    completion(.failure(batchError))
                } else {
                    print("All anchors deleted for user: \(userId)")
                    completion(.success(()))
                }
            }
        }
    }
    
    // MARK: - Delete Single Anchor
    func deleteAnchor(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = currentUser?.uid else {
            completion(.failure(NSError(domain: "FirebaseManager",
                                     code: -1,
                                     userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])))
            return
        }
        
        let anchorRef = db.collection("users").document(userId)
            .collection(stickersCollection).document(id)
        
        anchorRef.delete { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
}

// MARK: - PlaneGeometry Struct
struct PlaneGeometry {
    let center: SIMD3<Float>
    let extent: SIMD3<Float>
    let normal: SIMD3<Float>
    
    init(center: SIMD3<Float>, extent: SIMD3<Float>, normal: SIMD3<Float>) {
        self.center = center
        self.extent = extent
        self.normal = normal
    }
    
    var dictionary: [String: [Double]] {
        [
            "center": [Double(center.x), Double(center.y), Double(center.z)],
            "extent": [Double(extent.x), Double(extent.y), Double(extent.z)],
            "normal": [Double(normal.x), Double(normal.y), Double(normal.z)]
        ]
    }
    
    init?(dictionary: [String: [Double]]) {
        guard let centerArray = dictionary["center"],
              let extentArray = dictionary["extent"],
              let normalArray = dictionary["normal"],
              centerArray.count == 3,
              extentArray.count == 3,
              normalArray.count == 3 else {
            return nil
        }
        
        self.center = SIMD3<Float>(Float(centerArray[0]), Float(centerArray[1]), Float(centerArray[2]))
        self.extent = SIMD3<Float>(Float(extentArray[0]), Float(extentArray[1]), Float(extentArray[2]))
        self.normal = SIMD3<Float>(Float(normalArray[0]), Float(normalArray[1]), Float(normalArray[2]))
    }
}

// MARK: - AnchorData Struct
struct AnchorData {
    let id: String
    let transform: simd_float4x4
    let name: String
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let timestamp: Double
    var scale: SIMD3<Float>?
    var orientation: simd_quatf?
    var planeGeometry: PlaneGeometry?
    let userId: String?
    let createdAt: Date?
    let isPublic: Bool
    
    init?(dictionary: [String: Any]) {
        // Validate and parse required fields
        guard let id = dictionary["id"] as? String,
              let transformArray = dictionary["transform"] as? [Double],
              transformArray.count == 16,
              let name = dictionary["name"] as? String,
              let latitude = dictionary["latitude"] as? Double,
              let longitude = dictionary["longitude"] as? Double,
              let altitude = dictionary["altitude"] as? Double,
              let horizontalAccuracy = dictionary["horizontalAccuracy"] as? Double,
              let verticalAccuracy = dictionary["verticalAccuracy"] as? Double,
              let timestamp = dictionary["timestamp"] as? Double else {
            print("Error: Required fields missing or invalid in dictionary")
            return nil
        }
        
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.timestamp = timestamp
        
        // Convert the array of Doubles to simd_float4x4
        var columns = [SIMD4<Float>]()
        for i in stride(from: 0, to: 16, by: 4) {
            let column = SIMD4<Float>(
                Float(transformArray[i]),
                Float(transformArray[i + 1]),
                Float(transformArray[i + 2]),
                Float(transformArray[i + 3])
            )
            columns.append(column)
        }
        self.transform = simd_float4x4(columns: (columns[0], columns[1], columns[2], columns[3]))
        
        // Parse optional scale
        if let scaleArray = dictionary["scale"] as? [Double] {
            self.scale = SIMD3<Float>(
                Float(scaleArray[0]),
                Float(scaleArray[1]),
                Float(scaleArray[2])
            )
        }
        
        // Parse optional orientation
        if let orientationArray = dictionary["orientation"] as? [Double] {
            self.orientation = simd_quatf(
                vector: SIMD4<Float>(
                    Float(orientationArray[0]),
                    Float(orientationArray[1]),
                    Float(orientationArray[2]),
                    Float(orientationArray[3])
                )
            )
        }
        
        // Parse plane geometry if available
        if let planeGeometryDict = dictionary["planeGeometry"] as? [String: [Double]] {
            self.planeGeometry = PlaneGeometry(dictionary: planeGeometryDict)
        }
        
        // Parse user-specific fields
        self.userId = dictionary["userId"] as? String
        if let timestamp = dictionary["createdAt"] as? Timestamp {
            self.createdAt = timestamp.dateValue()
        } else {
            self.createdAt = nil
        }
        self.isPublic = dictionary["isPublic"] as? Bool ?? false
        
        print("Initialized AnchorData with id: \(id), name: \(name), location: (\(latitude), \(longitude))")
    }
    
    var location: CLLocation? {
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            timestamp: createdAt ?? Date(timeIntervalSince1970: timestamp)
        )
    }
}
