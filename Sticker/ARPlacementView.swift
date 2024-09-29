import SwiftUI
import RealityKit
import ARKit

struct ARPlacementView: View {
    let imageIndex: Int
    @ObservedObject var arViewModel: ARViewModel
    
    var body: some View {
        ZStack {
            ARViewContainer(arViewModel: arViewModel)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                Text("Tap to drop your sticker")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                Spacer().frame(height: 50)
                Button("Clear All") {
                                       arViewModel.clearAllStickers()
                                   }
                                   .foregroundColor(.white)
                                   .padding()
                                   .background(Color.red.opacity(0.7))
                                   .cornerRadius(10)
            }
        }
        .navigationBarTitleDisplayMode(.inline)            
            .onAppear {
                       arViewModel.setSelectedImage(imageIndex: imageIndex)
                       if arViewModel.arView == nil {
                           arViewModel.startARSession()
                       } else {
                           arViewModel.restorePlacedStickers()
                       }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arViewModel: ARViewModel
    
    func makeUIView(context: Context) -> ARView {
        return arViewModel.arView!
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}
