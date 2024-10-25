import SwiftUI
import RealityKit
import ARKit

/// View for placing AR stickers in the real world
struct ARPlacementView: View {
    // MARK: - Properties
    @ObservedObject var arViewModel: ARViewModel
    @Environment(\.presentationMode) var presentationMode
    let selectedImageIndex: Int
    
    // MARK: - State
    @State private var showConfirmationDialog = false
    
    var body: some View {
        ZStack {
            // AR View
            ARViewContainer(arViewModel: arViewModel)
                .edgesIgnoringSafeArea(.all)
            
            // Distance Indicator
            if let distance = arViewModel.getDistanceToNearestSticker() {
                VStack {
                    Spacer().frame(height: 50)
                    HStack {
                        Spacer()
                        Text("Nearest sticker: \(Int(distance)) meters")
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        Spacer()
                    }
                    Spacer()
                }
            }
            
            // Instructions and Controls
            VStack {
                Spacer().frame(height: 450)
                
                Text("Tap to drop your sticker")
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .shadow(radius: 2)
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button("Load Nearby (6m)") {
                                           arViewModel.loadNearbyStickers()
                                       }
                    Button("Clear Scene") {
                        arViewModel.clearAll()
                    }
                    .buttonStyle(ARActionButtonStyle())
                    
                    Button("Delete All Stickers") {
                        showConfirmationDialog = true
                    }
                    .buttonStyle(ARActionButtonStyle())
                }
                .padding(.vertical)
            }
            
            // Loading Indicator
            if arViewModel.isLoading {
                LoadingView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(arViewModel.isLoading)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if arViewModel.isLoading {
                    ProgressView()
                        .tint(.blue)
                }
            }
        }
        .onAppear {
            arViewModel.setSelectedImage(imageIndex: selectedImageIndex)
        }
        // Error Alert
        .alert("Error", isPresented: Binding(
            get: { arViewModel.error != nil },
            set: { if !$0 { arViewModel.error = nil } }
        )) {
            Button("OK") { arViewModel.error = nil }
        } message: {
            Text(arViewModel.error?.localizedDescription ?? "Unknown error")
        }
        // Confirmation Dialog
        .confirmationDialog(
            "Delete All Stickers?",
            isPresented: $showConfirmationDialog,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                arViewModel.deleteAllfromFirebase()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all stickers. This action cannot be undone.")
        }
    }
}

/// Container for ARView
struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arViewModel: ARViewModel
    
    func makeUIView(context: Context) -> ARView {
        return arViewModel.arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

/// Loading overlay view
struct LoadingView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                Text("Loading...")
                    .foregroundColor(.white)
                    .font(.subheadline)
            }
            .padding(20)
            .background(Color.black.opacity(0.7))
            .cornerRadius(10)
        }
    }
}

/// Custom button style for AR actions
struct ARActionButtonStyle: ButtonStyle {
    let color: Color
    
    init(color: Color = .red) {
        self.color = color
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(configuration.isPressed ?
                       color.opacity(0.9) :
                       color.opacity(0.7))
            .cornerRadius(10)
            .shadow(radius: configuration.isPressed ? 2 : 4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#if DEBUG
struct ARPlacementView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ARPlacementView(arViewModel: ARViewModel(), selectedImageIndex: 1)
        }
    }
}
#endif
