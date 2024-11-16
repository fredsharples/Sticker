//
//  ARSessionManager.swift
//  Sticker
//
//  Created by Fred Sharples on 11/16/24.
//


import RealityKit
import ARKit
import Combine
import SwiftUI

class ARSessionManager: NSObject, ARSessionDelegate {
    // MARK: - Published Properties
    @Published private(set) var isSessionReady: Bool = false
    @Published private(set) var sessionError: Error?
    
    // MARK: - Properties
    private weak var arView: ARView?
    private weak var anchorManager: ARAnchorManager?
    private var subscriptions = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(arView: ARView, anchorManager: ARAnchorManager) {
        self.arView = arView
        self.anchorManager = anchorManager
        super.init()
        
        setupSession()
        setupNotifications()
    }
    
    // MARK: - Session Setup
    private func setupSession() {
        arView?.session.delegate = self
        configureARSession()
    }
    
    private func configureARSession() {
        guard let arView = arView else { return }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            print("📱 Device supports LiDAR")
            configuration.sceneReconstruction = .mesh
            
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
                configuration.sceneReconstruction = .meshWithClassification
            }
        } else {
            print("📱 Device does not support LiDAR")
        }
        
        print("🚀 Starting AR session...")
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    // MARK: - Lifecycle Management
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppBackgrounding()
            }
            .store(in: &subscriptions)
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppForegrounding()
            }
            .store(in: &subscriptions)
    }
    
    private func handleAppBackgrounding() {
        print("📱 App entering background")
        arView?.session.pause()
        anchorManager?.reset()
        isSessionReady = false
    }
    
    private func handleAppForegrounding() {
        print("📱 App entering foreground")
        resetARSession()
    }
    
    // MARK: - Session Management
    func resetARSession() {
        print("🔄 Resetting AR session...")
        configureARSession()
        anchorManager?.reset()
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
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        print("📷 Camera tracking state changed: \(camera.trackingState)")
        switch camera.trackingState {
        case .normal:
            print("✅ Tracking normal")
            isSessionReady = true
        case .limited(let reason):
            print("⚠️ Tracking limited: \(reason)")
            isSessionReady = false
        case .notAvailable:
            print("❌ Tracking not available")
            isSessionReady = false
        @unknown default:
            break
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("❌ AR session failed: \(error)")
        sessionError = error
        isSessionReady = false
        resetARSession()
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("⚠️ AR session was interrupted")
        isSessionReady = false
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("✅ AR session interruption ended")
        resetARSession()
    }
    
    // MARK: - Cleanup
    deinit {
        print("🧹 Cleaning up ARSessionManager")
        subscriptions.removeAll()
    }
}