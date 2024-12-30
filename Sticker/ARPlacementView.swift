import SwiftUI
import RealityKit
import ARKit

// UIViewRepresentable for ARView
struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arViewModel: ARViewModel
    
    func makeUIView(context: Context) -> ARView {
        return arViewModel.arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

struct ARPlacementView: View {
    @ObservedObject var arViewModel: ARViewModel
    let selectedImageIndex: Int
    
    private var scanningFeedback: some View {
        Group {
            switch arViewModel.scanningState {
            case .initializing:
                Text("Initializing AR session...")
            case .scanning(let progress):
                Text("Scanning environment: \(Int(progress * 100))%")
            case .ready:
                Text("Tap to drop your sticker")
            case .insufficientFeatures:
                Text("Move device to scan more surfaces")
            }
        }
        .foregroundColor(.white)
        .padding(10)
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
    }

    private var controlPanel: some View {
        VStack(spacing: 15) {
            HStack(spacing: 20) {
                Button(action: arViewModel.loadSavedAnchors) {
                    VStack {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 20))
                        Text("Load")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .frame(width: 60)
                    .padding(.vertical, 10)
                    .background(arViewModel.isPlacementEnabled ? Color.blue : Color.gray)
                    .cornerRadius(10)
                }
                .disabled(!arViewModel.isPlacementEnabled)
                
                Button(action: arViewModel.clearAll) {
                    VStack {
                        Image(systemName: "xmark")
                            .font(.system(size: 24))
                        Text("Clear")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .frame(width: 60)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .cornerRadius(10)
                }
                //uncomment for delete everything button
//                Button(action: arViewModel.deleteAllFromFirebase) {
//                    VStack {
//                        Image(systemName: "trash")
//                            .font(.system(size: 18))
//                        Text("Delete")
//                            .font(.caption)
//                    }
//                    .foregroundColor(.white)
//                    .frame(width: 60)
//                    .padding(.vertical, 10)
//                    .background(Color.red)
//                    .cornerRadius(10)
//                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.black.opacity(0.75))
                .blur(radius: 3)
        )
        .padding(.bottom, 10)
    }
    
    var body: some View {
            ZStack {
                ARViewContainer(arViewModel: arViewModel)
                    .ignoresSafeArea(edges: [.top, .horizontal])
                
                VStack {
                    scanningFeedback
                    Spacer()
                    controlPanel
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                arViewModel.setSelectedImage(imageIndex: selectedImageIndex)
            }
        }
}
