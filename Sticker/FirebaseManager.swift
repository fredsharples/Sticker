import Firebase
import ARKit
import FirebaseFirestore
import FirebaseAuth
import RealityKit

class FirebaseManager {
    private let db = Firestore.firestore()
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
    func saveAnchor(anchor: ARAnchor, imageName: String) {
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
            "name": imageName
        ]
        
        db.collection(anchorsCollection).document(idString).setData(anchorData) { error in
            if let error = error {
                print("Error saving anchor: \(error.localizedDescription)")
            } else {
                print("Anchor saved successfully.")
                print("Saved transformArray: \(transformArray)")
                
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
            print("Loaded these anchors: \(anchors.map(\.name).joined(separator: ",")))")
            completion(anchors)
        }
    }
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

// MARK: - AnchorData Struct
struct AnchorData {
    let id: String
    let transform: simd_float4x4
    let name: String
    
    init?(dictionary: [String: Any]) {
        // Check for 'id'
        guard let id = dictionary["id"] as? String else {
            print("Error: 'id' not found or not a String")
            return nil
        }

        // Check for 'transform'
        guard let transformArray = dictionary["transform"] as? [Double], transformArray.count == 16 else {
            print("Error: 'transform' not found or incorrect format")
            return nil
        }

        // 'name' might be optional
        let name = dictionary["name"] as? String

        self.id = id
        self.name = name ?? "defaultName"

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
        print("Retrieved transformArray: \(transformArray)")
    }
    
    func toARAnchor() -> ARAnchor {
        let anchor = ARAnchor(name: name, transform: transform)
        return anchor
    }
}

