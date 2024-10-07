import SwiftUI
import RealityKit
import ARKit

struct ARPlacementView: View {
    
    @ObservedObject var arViewModel: ARViewModel
    let selectedImageIndex: Int
    
    var body: some View {
        ZStack {
            ARViewContainer(arViewModel: arViewModel)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer().frame(height: 650)
                Text("Tap to drop your sticker")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .padding()
                Button(action: arViewModel.saveCurrentAnchor) {
                        Text("Save")
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                .padding()
                Button(action: arViewModel.loadSavedAnchors) {
                    Text("Load")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
                Button("Clear All") {
                                       arViewModel.clearAll()
                                   }
                                   .foregroundColor(.white)
                                   .padding()
                                   .background(Color.red.opacity(0.7))
                                   .cornerRadius(10)
            }
        }
        .navigationBarTitleDisplayMode(.inline)            
            .onAppear {
                arViewModel.setSelectedImage(imageIndex: selectedImageIndex)
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arViewModel: ARViewModel
    
    func makeUIView(context: Context) -> ARView {
        return arViewModel.arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}
