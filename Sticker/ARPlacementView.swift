import SwiftUI
import RealityKit
import ARKit

struct ARPlacementView: View {
    @ObservedObject var arViewModel: ARViewModel
    let selectedImageIndex: Int
    
    var body: some View {
        ZStack {
            // AR View takes up full screen
            ARViewContainer(arViewModel: arViewModel)
                .ignoresSafeArea(edges: [.top, .horizontal]) // Don't ignore bottom safe area
            
            VStack {
                // Main content area
                VStack {
                    Spacer()
                    
                    Text("Tap to drop your sticker")
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                }
                
                Spacer()
                    .frame(height: 10) // Add extra space above the control panel
                
                // Control Panel
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
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                        
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
                        
                        Button(action: arViewModel.deleteAllFromFirebase) {
                            VStack {
                                Image(systemName: "trash")
                                    .font(.system(size: 18))
                                Text("Delete")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .frame(width: 60)
                            .padding(.vertical, 10)
                            .background(Color.red)
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(.vertical, 10) // Increased vertical padding inside the control panel
                .padding(.horizontal)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.black.opacity(0.75))
                        .blur(radius: 3)
                )
                .padding(.bottom, 10) // Maintain bottom spacing for tab bar
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
