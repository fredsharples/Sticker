//
//  ARLocationManager.swift
//  Sticker
//
//  Created by Fred Sharples on 11/5/24.
//


import CoreLocation
import CoreMotion

class ARLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    // MARK: - Published Properties
    @Published var currentLocation: CLLocation?
    @Published var heading: CLHeading?
    @Published var motionData: CMDeviceMotion?
    
    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let loadingRange: Double = 100 // meters
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupLocationServices()
        setupMotionServices()
    }
    
    // MARK: - Setup Methods
    private func setupLocationServices() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.pausesLocationUpdatesAutomatically = false
        
        if #available(iOS 11.0, *) {
            locationManager.showsBackgroundLocationIndicator = true
        }
        
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
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
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              location.horizontalAccuracy < 20 else { return }
        
        currentLocation = location
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error)")
    }
    
    // MARK: - Public Methods
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        motionManager.stopDeviceMotionUpdates()
    }
    
    // MARK: - Cleanup
    func cleanup() {
        stopTracking()
    }
}