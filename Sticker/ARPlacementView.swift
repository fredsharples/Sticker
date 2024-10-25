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
            
            if let distance = arViewModel.getDistanceToNearestSticker() {
                            Text("Nearest sticker: \(Int(distance)) meters")
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
            
            VStack {
                Spacer().frame(height: 450)
                Text("Tap to drop your sticker")
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    
//                Button(action: arViewModel.saveCurrentAnchor) {
//                        Text("Save")
//                           .padding(10)
//                            .background(Color.blue)
//                            .foregroundColor(.white)
//                            .cornerRadius(10)
//                    }
             
                Button(action: arViewModel.loadSavedAnchors) {
                    Text("Load")
                        .padding(10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                Button("Clear All") {
                                       arViewModel.clearAll()
                                   }
                                   .foregroundColor(.white)
                                   .padding(10)
                                   .background(Color.red.opacity(0.7))
                                   .cornerRadius(10)
                Button("Delete All From Firebase") {
                                       arViewModel.deleteAllfromFirebase()
                                   }
                                   .foregroundColor(.white)
                                   .padding(10)
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
