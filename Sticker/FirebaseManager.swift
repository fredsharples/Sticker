import Firebase
import FirebaseFirestore
import FirebaseAuth
import RealityKit

// MARK: - FirebaseManager Class
class FirebaseManager {
    private let db = Firestore.firestore()
    private let anchorsCollection = "stickers"
    
    // MARK: - Initialization
    init() {
       
    }
    
    // MARK: - Login
    func loginFirebase(completion: @escaping (Result<User, Error>) -> Void) {
        AuthManager.shared.signInAnonymously { result in
            switch result {
            case .success(let user):
                print("User signed in anonymously with ID: \(user.uid)")
                completion(.success(user))
            case .failure(let error):
                print("Error signing in: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    // MARK: - Save Anchor
    
    func saveAnchor(anchorData: [String: Any]) {
            let idString = anchorData["id"] as! String
            
            db.collection(anchorsCollection).document(idString).setData(anchorData) { error in
                if let error = error {
                    print("Error saving anchor: \(error.localizedDescription)")
                } else {
                    print("Anchor saved successfully with geolocation.")
                }
            }
        }
    
  
    
    // MARK: - Load Anchors
    func loadAnchors(completion: @escaping (Result<[AnchorData], Error>) -> Void) {
        db.collection(anchorsCollection).getDocuments { snapshot, error in
            if let error = error {
                print("Error loading anchors: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("No documents found in collection \(self.anchorsCollection).")
                completion(.success([]))
                return
            }
            
            let anchors = documents.compactMap { doc -> AnchorData? in
                let data = doc.data()
                return AnchorData(dictionary: data)
            }
            print("Loaded these anchors: \(anchors.map(\.name).joined(separator: ", "))")
            completion(.success(anchors))
        }
    }
    
    // MARK: - Delete All Anchors
    func deleteAllAnchors(completion: @escaping (Result<Void, Error>) -> Void) {
        db.collection(anchorsCollection).getDocuments { (snapshot, error) in
            if let error = error {
                print("Error fetching documents: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let snapshot = snapshot else {
                print("No documents found in collection \(self.anchorsCollection).")
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
                    print("All anchors deleted successfully from collection \(self.anchorsCollection).")
                    completion(.success(()))
                }
            }
        }
    }
}

// MARK: - AuthManager Class
class AuthManager {
    static let shared = AuthManager()
    
    private init() {}
    
    func signInAnonymously(completion: @escaping (Result<User, Error>) -> Void) {
        Auth.auth().signInAnonymously { authResult, error in
            if let error = error {
                completion(.failure(error))
            } else if let user = authResult?.user {
                completion(.success(user))
            } else {
                let unknownError = NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown authentication error."])
                completion(.failure(unknownError))
            }
        }
    }
}

// MARK: - AnchorData Struct
// Update this struct in FirebaseManager.swift
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
            print("Error: Required fields missing or invalid in dictionary: \(dictionary)")
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
        if let planeGeometryDict = dictionary["planeGeometry"] as? [String: [Double]] {
                    self.planeGeometry = PlaneGeometry(dictionary: planeGeometryDict)
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
       
        print("Initialized AnchorData with id: \(id), name: \(name), location: (\(latitude), \(longitude))")
    }
    
    // Method to convert AnchorData to AnchorEntity
    func toAnchorEntity() -> AnchorEntity {
        let anchorEntity = AnchorEntity(world: transform)
        anchorEntity.name = name
        
        // Apply scale if available
        if let scale = scale {
            anchorEntity.scale = scale
        }
        
        // Apply orientation if available
        if let orientation = orientation {
            anchorEntity.orientation = orientation
        }
        
        return anchorEntity
    }
}

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
              let normalArray = dictionary["normal"] else { return nil }
        
        self.center = SIMD3<Float>(Float(centerArray[0]), Float(centerArray[1]), Float(centerArray[2]))
        self.extent = SIMD3<Float>(Float(extentArray[0]), Float(extentArray[1]), Float(extentArray[2]))
        self.normal = SIMD3<Float>(Float(normalArray[0]), Float(normalArray[1]), Float(normalArray[2]))
    }
}
