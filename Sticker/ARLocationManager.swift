//
//  ARLocationManager.swift
//  Sticker
//
//  Created by Fred Sharples on 11/5/24.
//

import CoreLocation
import CoreMotion

class ARLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var currentLocation: CLLocation? // Added back for ARViewModel
    @Published var heading: CLHeading? // Added back for ARViewModel
    @Published var motionData: CMDeviceMotion? // Added back for ARViewModel
    
    // MotionManager for device motion data
    private let motionManager = CMMotionManager()
    
    // This callback will only be triggered once when the first location is obtained
    var onFirstLocationUpdate: ((CLLocation) -> Void)?
    private var hasReceivedInitialLocation = false
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        
        setupMotionServices()
    }
    
    private func setupMotionServices() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.1
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
                guard let motion = motion, error == nil else { return }
                self?.motionData = motion
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location
        self.currentLocation = location // Update both properties for compatibility
        
        // Only call the callback for the first location update
        if !hasReceivedInitialLocation {
            hasReceivedInitialLocation = true
            print("LocationManager: First location received: \(location.coordinate)")
            onFirstLocationUpdate?(location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined, .restricted, .denied:
            print("Location access not available")
        case .authorizedAlways, .authorizedWhenInUse:
            print("Location access granted")
        @unknown default:
            break
        }
    }
    
    // Added back for ARViewModel
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        motionManager.stopDeviceMotionUpdates()
    }
    
    // Added back for ARViewModel
    func cleanup() {
        stopTracking()
    }
}
