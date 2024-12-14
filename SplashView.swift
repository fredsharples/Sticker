// SplashView.swift
import SwiftUI

struct SplashView: View {
    @Binding var isLoading: Bool
    
    var body: some View {
        ZStack {
            Color("LaunchBackgroundColor")
                .ignoresSafeArea()
            
            VStack {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 150, height: 150)
                
                Text("Stickers")
                    .font(.largeTitle)
                    .bold()
                    .padding(.top)
            }
        }
        .onAppear {
            // Simulate minimum splash screen time
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    isLoading = false
                }
            }
        }
    }
}