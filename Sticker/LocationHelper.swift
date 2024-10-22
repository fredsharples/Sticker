//
//  LocationHelper.swift
//  Sticker
//
//  Created by Fred Sharples on 10/22/24.
//

import CoreLocation

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
