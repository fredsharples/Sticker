//
//  AuthManager.swift
//  Sticker
//
//  Created by Fred Sharples on 12/14/24.
//


import Foundation
import FirebaseAuth
import Security

class AuthManager {
    static let shared = AuthManager()
    private let keychainKey = "com.sticker.anonymousUID"
    
    private init() {}
    
    func signInAnonymously(completion: @escaping (Result<User, Error>) -> Void) {
        // First try to retrieve existing UID
        if let existingUID = retrieveUID() {
            // Try to sign in with existing UID
            Auth.auth().signIn(withCustomToken: existingUID) { [weak self] (result, error) in
                if let user = result?.user {
                    completion(.success(user))
                } else {
                    // If existing UID fails, create new anonymous account
                    self?.createNewAnonymousUser(completion: completion)
                }
            }
        } else {
            // No existing UID, create new anonymous account
            createNewAnonymousUser(completion: completion)
        }
    }
    
    private func createNewAnonymousUser(completion: @escaping (Result<User, Error>) -> Void) {
        Auth.auth().signInAnonymously { [weak self] (result, error) in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let user = result?.user {
                // Store the UID in keychain
                self?.storeUID(user.uid)
                completion(.success(user))
            } else {
                let error = NSError(domain: "AuthManager",
                                  code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to create anonymous user"])
                completion(.failure(error))
            }
        }
    }
    
    private func storeUID(_ uid: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: uid.data(using: .utf8)!
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add the new item
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Failed to store UID in keychain: \(status)")
        }
    }
    
    private func retrieveUID() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess,
           let data = dataTypeRef as? Data,
           let uid = String(data: data, encoding: .utf8) {
            return uid
        }
        
        return nil
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            // Optionally clear the stored UID if you want to force a new anonymous account
            // clearStoredUID()
        } catch {
            print("Error signing out: \(error)")
        }
    }
    
    private func clearStoredUID() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}