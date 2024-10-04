import Firebase
import ARKit
import FirebaseFirestore
import FirebaseFirestoreCombineSwift
import FirebaseAuth
import RealityKit

class FirebaseManager {
    private let db = Firestore.firestore()
    private let collectionName = "stickers"
    private let anchorsCollection = "anchors"
   
    // MARK: - Login
    func loginFirebase (){
        AuthManager.shared.signInAnonymously { result in
            switch result {
            case .success(let user):
                print("User signed in anonymously with ID: \(user.uid)")
                // Now you can save or load anchor entities
                //self.saveAnchorEntities(anchors)  // or loadAnchorEntities()
            case .failure(let error):
                print("Error signing in: \(error.localizedDescription)")
            }
        }
        
    }
    
    // MARK: - Save Anchor
    func saveAnchor(anchor: ARAnchor) {
            let idString = anchor.identifier.uuidString
            let transform = anchor.transform
            
            // Serialize the transform matrix into an array
            let transformArray = [
                transform.columns.0.x, transform.columns.0.y, transform.columns.0.z, transform.columns.0.w,
                transform.columns.1.x, transform.columns.1.y, transform.columns.1.z, transform.columns.1.w,
                transform.columns.2.x, transform.columns.2.y, transform.columns.2.z, transform.columns.2.w,
                transform.columns.3.x, transform.columns.3.y, transform.columns.3.z, transform.columns.3.w
            ]
            
            let anchorData: [String: Any] = [
                "id": idString,
                "transform": transformArray,
                "name": anchor.name ?? ""
            ]
            
            db.collection(anchorsCollection).document(idString).setData(anchorData) { error in
                if let error = error {
                    print("Error saving anchor: \(error.localizedDescription)")
                } else {
                    print("Anchor saved successfully.")
                }
            }
        }
    
    // MARK: - Load Anchors
    func loadAnchors(completion: @escaping ([AnchorData]) -> Void) {
            db.collection(anchorsCollection).getDocuments { snapshot, error in
                if let error = error {
                    print("Error loading anchors: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let anchors = documents.compactMap { doc -> AnchorData? in
                    let data = doc.data()
                    return AnchorData(dictionary: data)
                }
                completion(anchors)
            }
        }
        
    

//    func storePlaneData(_ planeData: [String: Any], withID id: String, completion: @escaping (Result<Void, Error>) -> Void) {
//        guard let userId = Auth.auth().currentUser?.uid else {
//            completion(.failure(NSError(domain: "FirebaseManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "User not signed in"])))
//            return
//        }
//        
//        //let db = Firestore.firestore()
//        db.collection("planes").document(id).setData(planeData) { error in
//            if let error = error {
//                print("Error saving plane data: \(error.localizedDescription)")
//            } else {
//                print("Plane data saved successfully.")
//            }
//        }
//    }
    
    
//    func saveAnchorEntities(_ anchors: [AnchorEntity], completion: @escaping (Result<Void, Error>) -> Void) {
//            guard let userId = Auth.auth().currentUser?.uid else {
//                completion(.failure(NSError(domain: "FirebaseManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "User not signed in"])))
//                return
//            }
//        
//        let anchorData = anchors.map { anchor -> [String: Any] in
//            let data = AnchorEntityData(
//                id: anchor.id.description,
//                position: anchor.position,
//                orientation: anchor.orientation
//            )
//            return try! Firestore.Encoder().encode(data)
//        }
//        
//        db.collection(collectionName).document(userId).setData(["anchors": anchorData]) { error in
//            if let error = error {
//                print("Error saving anchor entities: \(error)")
//            } else {
//                print("Anchor entities saved successfully")
//            }
//        }
//    }
    
//    func loadAnchorEntities(completion: @escaping (Result<[AnchorEntity], Error>) -> Void) {
//            guard let userId = Auth.auth().currentUser?.uid else {
//                completion(.failure(NSError(domain: "FirebaseManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "User not signed in"])))
//                return
//            }
//        
//        db.collection(collectionName).document(userId).getDocument { document, error in
//            if let error = error {
//                            completion(.failure(error))
//                            return
//                        }
//            guard let document = document, document.exists, let anchorData = document.data()?["anchors"] as? [[String: Any]] else {
//                            completion(.success([]))
//                            return
//                        }
//            
//            let anchors: [AnchorEntity] = anchorData.compactMap { data in
//                guard let anchorEntityData = try? Firestore.Decoder().decode(AnchorEntityData.self, from: data) else { return nil }
//                let anchor = AnchorEntity()
//                anchor.position = anchorEntityData.position
//                anchor.orientation = anchorEntityData.orientation
//                return anchor
//            }
//            
//            completion(.success(anchors))
//        }
//    }
    
}

// MARK: - Auth Manager
class AuthManager {
    static let shared = AuthManager()
    
    private init() {}
    
    func signInAnonymously(completion: @escaping (Result<User, Error>) -> Void) {
        Auth.auth().signInAnonymously { authResult, error in
            if let error = error {
                completion(.failure(error))
            } else if let user = authResult?.user {
                completion(.success(user))
            }
        }
    }
}
// Extension to decompose simd_float4x4 into translation, rotation, and scale
//extension simd_float4x4 {
//    var translation: SIMD3<Float> {
//        return columns.3.xyz
//    }
//
//    var rotation: simd_quatf {
//        let upperLeft = simd_float3x3(columns.0.xyz, columns.1.xyz, columns.2.xyz)
//        return simd_quaternion(upperLeft)
//    }
//
//    var scale: SIMD3<Float> {
//        let scaleX = length(columns.0.xyz)
//        let scaleY = length(columns.1.xyz)
//        let scaleZ = length(columns.2.xyz)
//        return SIMD3<Float>(scaleX, scaleY, scaleZ)
//    }
//}
//extension SIMD4<Float> {
//    var xyz: SIMD3<Float> {
//        return SIMD3<Float>(x, y, z)
//    }
//}

// MARK: - AnchorData Struct
struct AnchorData {
    let id: String
    let transform: simd_float4x4
    let name: String
    
    init?(dictionary: [String: Any]) {
        guard
            let id = dictionary["id"] as? String,
            let transformArray = dictionary["transform"] as? [NSNumber],
            transformArray.count == 16,
            let name = dictionary["name"] as? String
        else {
            return nil
        }
        
        self.id = id
        self.name = name
        
        var columns = [SIMD4<Float>]()
        for i in stride(from: 0, to: 16, by: 4) {
            let column = SIMD4<Float>(
                transformArray[i].floatValue,
                transformArray[i + 1].floatValue,
                transformArray[i + 2].floatValue,
                transformArray[i + 3].floatValue
            )
            columns.append(column)
        }
        self.transform = simd_float4x4(columns: (columns[0], columns[1], columns[2], columns[3]))
    }
    
    func toARAnchor() -> ARAnchor {
        let anchor = ARAnchor(name: name, transform: transform)
        return anchor
    }
}


//struct AnchorEntityData: Codable {
//    let id: String
//    let position: SIMD3<Float>
//    let orientation: simd_quatf
//
//    enum CodingKeys: String, CodingKey {
//        case id
//        case positionX, positionY, positionZ
//        case orientationX, orientationY, orientationZ, orientationW
//    }
//
//    init(id: String, position: SIMD3<Float>, orientation: simd_quatf) {
//        self.id = id
//        self.position = position
//        self.orientation = orientation
//    }
//
//    init(from decoder: Decoder) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//        id = try container.decode(String.self, forKey: .id)
//        
//        let x = try container.decode(Float.self, forKey: .positionX)
//        let y = try container.decode(Float.self, forKey: .positionY)
//        let z = try container.decode(Float.self, forKey: .positionZ)
//        position = SIMD3<Float>(x: x, y: y, z: z)
//        
//        let qx = try container.decode(Float.self, forKey: .orientationX)
//        let qy = try container.decode(Float.self, forKey: .orientationY)
//        let qz = try container.decode(Float.self, forKey: .orientationZ)
//        let qw = try container.decode(Float.self, forKey: .orientationW)
//        orientation = simd_quatf(ix: qx, iy: qy, iz: qz, r: qw)
//    }
//
//    func encode(to encoder: Encoder) throws {
//        var container = encoder.container(keyedBy: CodingKeys.self)
//        try container.encode(id, forKey: .id)
//        
//        try container.encode(position.x, forKey: .positionX)
//        try container.encode(position.y, forKey: .positionY)
//        try container.encode(position.z, forKey: .positionZ)
//        
//        try container.encode(orientation.imag.x, forKey: .orientationX)
//        try container.encode(orientation.imag.y, forKey: .orientationY)
//        try container.encode(orientation.imag.z, forKey: .orientationZ)
//        try container.encode(orientation.real, forKey: .orientationW)
//    }
//}
