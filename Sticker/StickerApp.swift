//
//  StickerApp.swift
//  Sticker
//
//  Created by Fred Sharples on 9/24/24.
//
import Firebase
import SwiftUI

@main
struct StickerApp: App {
    @State private var isLoading = true
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
//                if isLoading {
//                    SplashView(isLoading: $isLoading)
//                } else {
                    ContentView()
                //}
            }
        }
    }
}
