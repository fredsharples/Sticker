import Firebase
import ARKit
import FirebaseFirestore
import FirebaseFirestoreCombineSwift
import FirebaseAuth
import RealityKit

class FirestoreManager {
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
    func saveAnchor(anchor: ARAnchor, materialData: MaterialData?) {
        let idString = anchor.identifier.uuidString
        let transformArray = anchor.transform.toArray()
        let name = anchor.name ?? ""

        var anchorData: [String: Any] = [
            "id": idString,
            "transform": transformArray,
            "name": name
        ]

        if let materialData = materialData {
            anchorData["material"] = materialData.toDictionary()
        }

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
                print("No anchors found.")
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
import ARKit
import simd

// MARK: - AnchorData Struct

struct AnchorData {
    let id: String
    let transform: simd_float4x4
    let name: String
    let materialData: MaterialData?

    // Initializer to create AnchorData from a dictionary (e.g., data retrieved from Firestore)
    init?(dictionary: [String: Any]) {
        // Extract 'id' from the dictionary
        guard let id = dictionary["id"] as? String else {
            print("Error: 'id' not found or not a String")
            return nil
        }

        // Extract 'transform' array from the dictionary and ensure it has 16 elements
        guard let transformArray = dictionary["transform"] as? [Double], transformArray.count == 16 else {
            print("Error: 'transform' not found or incorrect format")
            return nil
        }

        // Reconstruct the simd_float4x4 transform matrix from the array
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
        let transform = simd_float4x4(columns: (columns[0], columns[1], columns[2], columns[3]))

        // Extract 'name' from the dictionary or provide a default value
        let name = dictionary["name"] as? String ?? "defaultName"

        // Extract 'material' data from the dictionary
        var materialData: MaterialData? = nil
        if let materialDict = dictionary["material"] as? [String: Any] {
            materialData = MaterialData(dictionary: materialDict)
        }

        // Initialize properties
        self.id = id
        self.transform = transform
        self.name = name
        self.materialData = materialData
    }

    // Method to convert AnchorData to a dictionary suitable for Firestore storage
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "transform": transform.toArray(),
            "name": name
        ]
        if let materialData = materialData {
            dict["material"] = materialData.toDictionary()
        }
        return dict
    }

    // Method to create an ARAnchor from the AnchorData
    func toARAnchor() -> ARAnchor {
        return ARAnchor(name: name, transform: transform)
    }
}

// MARK: - MaterialData Struct

struct MaterialData {
    let imageIndex: Int
    let tintAlpha: Float

    // Initializer to create MaterialData from a dictionary
    init?(dictionary: [String: Any]) {
        guard let imageIndex = dictionary["imageIndex"] as? Int,
              let tintAlpha = dictionary["tintAlpha"] as? Float else {
            print("Error: 'materialData' missing or invalid")
            return nil
        }
        self.imageIndex = imageIndex
        self.tintAlpha = tintAlpha
    }

    // Method to convert MaterialData to a dictionary for Firestore storage
    func toDictionary() -> [String: Any] {
        return [
            "imageIndex": imageIndex,
            "tintAlpha": tintAlpha
        ]
    }
}

// MARK: - Extension for simd_float4x4

extension simd_float4x4 {
    // Method to convert the transform matrix to an array of Floats for storage
    func toArray() -> [Float] {
        return [
            columns.0.x, columns.0.y, columns.0.z, columns.0.w,
            columns.1.x, columns.1.y, columns.1.z, columns.1.w,
            columns.2.x, columns.2.y, columns.2.z, columns.2.w,
            columns.3.x, columns.3.y, columns.3.z, columns.3.w
        ]
    }
}


