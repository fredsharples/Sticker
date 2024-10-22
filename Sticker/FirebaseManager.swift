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
        // Optionally, configure Firebase if not done elsewhere
        // FirebaseApp.configure()
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
    
    func saveSticker(data: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
            db.collection("stickers").addDocument(data: data) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    
  
    func fetchNearbyStickerData(latitude: Double, longitude: Double, radiusInKm: Double, completion: @escaping ([String: Any]) -> Void) {
            // Convert radius from km to degrees (approximate)
            let radiusInDegrees = radiusInKm / 111.32
            
            let latMin = latitude - radiusInDegrees
            let latMax = latitude + radiusInDegrees
            let lonMin = longitude - radiusInDegrees
            let lonMax = longitude + radiusInDegrees
            
            db.collection("stickers")
                .whereField("latitude", isGreaterThan: latMin)
                .whereField("latitude", isLessThan: latMax)
                .getDocuments { (snapshot, error) in
                    if let error = error {
                        print("Error getting documents: \(error)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        print("No documents found")
                        return
                    }
                    
                    for document in documents {
                        let data = document.data()
                        guard let stickerLat = data["latitude"] as? Double,
                              let stickerLon = data["longitude"] as? Double else {
                            continue
                        }
                        
                        // Secondary filter for longitude
                        if stickerLon >= lonMin && stickerLon <= lonMax {
                            // Calculate precise distance
                            let stickerLocation = CLLocation(latitude: stickerLat, longitude: stickerLon)
                            let centerLocation = CLLocation(latitude: latitude, longitude: longitude)
                            let distance = stickerLocation.distance(from: centerLocation) / 1000 // Convert to km
                            
                            if distance <= radiusInKm {
                                completion(data)
                            }
                        }
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
struct AnchorData {
    let id: String
    let transform: simd_float4x4
    let name: String
    
    init?(dictionary: [String: Any]) {
        // Validate and parse 'id'
        guard let id = dictionary["id"] as? String else {
            print("Error: 'id' not found or not a String in dictionary: \(dictionary)")
            return nil
        }

        // Validate and parse 'transform'
        guard let transformArray = dictionary["transform"] as? [Double], transformArray.count == 16 else {
            print("Error: 'transform' not found or incorrect format in dictionary: \(dictionary)")
            return nil
        }

        // Parse 'name', defaulting if necessary
        let name = dictionary["name"] as? String ?? "defaultName"
        
        self.id = id
        self.name = name
        
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
        
        print("Initialized AnchorData with id: \(id), name: \(name), transform: \(transformArray)")
    }
    
    // Method to convert AnchorData to AnchorEntity
    func toAnchorEntity() -> AnchorEntity {
        let anchorEntity = AnchorEntity(world: transform)
        anchorEntity.name = name
        return anchorEntity
    }
}
