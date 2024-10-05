import SwiftUI

struct ContentView: View {
    let columns: [GridItem] = Array(repeating: .init(.flexible()), count: 3)
    let imageCount = 12 // Total number of images to display
    @StateObject private var arViewModel = ARViewModel()
    
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(1...imageCount, id: \.self) { index in
                        NavigationLink(destination: ARPlacementView(imageIndex: index, arViewModel: arViewModel)) {
                            Image(uiImage: loadImage(index: index))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 100)
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(10)
                        }
                    }
                }
                .padding()
                //                Button(action: arViewModel.saveCurrentAnchor) {
                //                    Text("Save")
                //                        .padding()
                //                        .background(Color.blue)
                //                        .foregroundColor(.white)
                //                        .cornerRadius(10)
                //                }
                //                .padding()
                //                Button(action: {
                //                    arViewModel.loadSavedAnchors()
                //                }) {
                //                    Text("Load Anchors")
                //                        .padding()
                //                        .background(Color.orange)
                //                        .foregroundColor(.white)
                //                        .cornerRadius(10)
            }
            
            
        }
        
        
        .navigationTitle("Choose your sticker")
    }
}

//    func savePlacedStickers() {
//        arViewModel.savePlacedStickers()
//    }

func loadImage(index: Int) -> UIImage {
    let imageName = String(format: "image_%04d", index)
    if let image = UIImage(named: imageName) {
        return image
    } else {
        print("Failed to load image: \(imageName)")
        return UIImage(systemName: "photo") ?? UIImage()
    }
}



//struct ARViewContainer: UIViewRepresentable {
//    @ObservedObject var arViewModel: ARViewModel
//    
//    func makeUIView(context: Context) -> ARView {
//        return arViewModel.arView
//    }
//    
//    func updateUIView(_ uiView: ARView, context: Context) {}
//}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
