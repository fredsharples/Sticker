import SwiftUI

struct ContentView: View {
    let columns: [GridItem] = Array(repeating: .init(.flexible()), count: 3)
    let imageCount = 12 // Total number of images to display
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(1...imageCount, id: \.self) { index in
                        NavigationLink(destination: ARPlacementView(imageIndex: index)) {
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
            }
            .navigationTitle("Choose your sticker")
        }
    }
    
    func loadImage(index: Int) -> UIImage {
        let imageName = String(format: "image_%04d", index)
        if let image = UIImage(named: imageName) {
            return image
        } else {
            print("Failed to load image: \(imageName)")
            return UIImage(systemName: "photo") ?? UIImage()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
