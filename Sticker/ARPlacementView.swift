import SwiftUI
import RealityKit
import ARKit

struct ARPlacementView: View {
    let imageIndex: Int
    @StateObject private var arViewModel = ARViewModel()
    @State private var debugInfo: String = ""
    
    var body: some View {
        ZStack {
            ARViewContainer(arViewModel: arViewModel)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                HStack {
                    Text("Stickers: \(arViewModel.placedStickersCount)/100")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                    
                    Spacer()
                    
                    Button("Clear All") {
                        arViewModel.clearAllStickers()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red.opacity(0.7))
                    .cornerRadius(10)
                }
                .padding()
                
                Spacer()
                
                Text("Tap to drop your sticker")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                Spacer().frame(height: 50)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if arViewModel.arView == nil {
                arViewModel.startARSession()
            }
            arViewModel.changeSelectedImage(imageIndex: imageIndex)
            updateDebugInfo()
        }
    }
    func updateDebugInfo() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if let arView = arViewModel.arView {
                    debugInfo = "ARView created: \(arView.session.currentFrame != nil ? "Yes" : "No")\n"
                    //debugInfo += "Camera tracking state: \(arView.session.currentFrame?.camera.trackingState.description ?? "Unknown")"
                } else {
                    debugInfo = "ARView not created"
                }
                updateDebugInfo()
            }
        }
}
struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arViewModel: ARViewModel
    
    func makeUIView(context: Context) -> ARView {
        print("Making UIView for ARViewContainer")
        if let existingARView = arViewModel.arView {
            print("Using existing ARView")
            return existingARView
        } else {
            print("Creating new ARView")
            let newARView = ARView(frame: .zero)
            arViewModel.arView = newARView
            arViewModel.startARSession()
            return newARView
        }
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        print("Updating UIView for ARViewContainer")
    }
}

extension ARCamera.TrackingState.Reason: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .initializing:
            return "Initializing"
        case .excessiveMotion:
            return "Excessive Motion"
        case .insufficientFeatures:
            return "Insufficient Features"
        case .relocalizing:
            return "Relocalizing"
        @unknown default:
            return "Unknown"
        }
    }
}


