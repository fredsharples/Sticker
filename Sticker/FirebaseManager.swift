import Firebase
import FirebaseFirestore
import FirebaseAuth
import RealityKit
import CoreLocation

// MARK: - FirebaseManager Class
class FirebaseManager : NSObject, ObservableObject {
    private let db = Firestore.firestore()
        private let anchorsCollection = "stickers"
        
        @Published var isLoading = false
        @Published var error: Error?
        @Published var stickers: [String: Any] = [:]
        
        override init() {
            super.init()
        }
    
    // MARK: - Login
    /// Performs anonymous authentication with Firebase
        /// - Parameter completion: Callback with Result containing User on success or Error on failure
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
    
    /// Saves a new sticker to Firebase
        /// - Parameters:
        ///   - data: Dictionary containing sticker data
        ///   - completion: Callback with Result indicating success or failure
        func saveSticker(data: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
            isLoading = true
            error = nil
            
            db.collection(anchorsCollection).addDocument(data: data) { [weak self] error in
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    self.error = error
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    
    /// Fetches stickers within a specified radius of a location
        /// - Parameters:
        ///   - latitude: Center point latitude
        ///   - longitude: Center point longitude
        ///   - radiusInKm: Search radius in kilometers
        ///   - completion: Callback with sticker data dictionary
        func fetchNearbyStickerData(latitude: Double,
                                   longitude: Double,
                                   radiusInKm: Double,
                                   completion: @escaping ([String: Any]) -> Void) {
            let radiusInDegrees = radiusInKm / 111.32
            let latMin = latitude - radiusInDegrees
            let latMax = latitude + radiusInDegrees
            
            isLoading = true
            error = nil
            
            db.collection(anchorsCollection)
                .whereField("latitude", isGreaterThan: latMin)
                .whereField("latitude", isLessThan: latMax)
                .getDocuments { [weak self] (snapshot, error) in
                    guard let self = self else { return }
                    self.isLoading = false
                    
                    if let error = error {
                        print("Error getting documents: \(error)")
                        self.error = error
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        print("No documents found")
                        return
                    }
                    
                    for document in documents {
                        let data = document.data()
                        if LocationHelper.isLocation(
                            data["latitude"] as? Double ?? 0,
                            data["longitude"] as? Double ?? 0,
                            withinRadiusKm: radiusInKm,
                            ofLocation: latitude, longitude) {
                            self.stickers[document.documentID] = data
                            completion(data)
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
    /// Deletes all stickers from Firebase
       /// - Parameter completion: Callback with Result indicating success or failure
       func deleteAllAnchors(completion: @escaping (Result<Void, Error>) -> Void) {
           isLoading = true
           error = nil
           
           db.collection(anchorsCollection).getDocuments { [weak self] (snapshot, error) in
               guard let self = self else { return }
               
               if let error = error {
                   self.isLoading = false
                   completion(.failure(error))
                   return
               }
               
               let batch = self.db.batch()
               snapshot?.documents.forEach { batch.deleteDocument($0.reference) }
               
               batch.commit { error in
                   self.isLoading = false
                   if let error = error {
                       self.error = error
                       completion(.failure(error))
                   } else {
                       self.stickers.removeAll()
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

struct LocationHelper {
    static func isLocation(_ lat1: Double, _ lon1: Double,
                          withinRadiusKm radius: Double,
                          ofLocation lat2: Double, _ lon2: Double) -> Bool {
        let location1 = CLLocation(latitude: lat1, longitude: lon1)
        let location2 = CLLocation(latitude: lat2, longitude: lon2)
        let distanceInKm = location1.distance(from: location2) / 1000
        return distanceInKm <= radius
    }
}
