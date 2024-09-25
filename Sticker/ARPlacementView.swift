import SwiftUI
import RealityKit
import ARKit

struct ARPlacementView: View {
    let imageIndex: Int
    @StateObject private var arViewModel = ARViewModel()
    
    var body: some View {
        ZStack {
            ARViewContainer(arViewModel: arViewModel)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                Image(uiImage: loadImage(index: imageIndex))
                    .resizable()
                    .scaledToFit()
                    .frame(width: UIScreen.main.bounds.width * 0.15, height: UIScreen.main.bounds.width * 0.15)
                    .background(Color.white.opacity(0.5))
                    .cornerRadius(10)
                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            arViewModel.startARSession()
        }
    }
    
    private func loadImage(index: Int) -> UIImage {
        let imageName = String(format: "image_%04d", index)
        return UIImage(named: imageName) ?? UIImage(systemName: "photo")!
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arViewModel: ARViewModel
    
    func makeUIView(context: Context) -> ARView {
        return arViewModel.arView!
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}
