import SwiftUI

struct PickerView: View {
    let columns: [GridItem] = Array(repeating: .init(.flexible()), count: 3)
    let imageCount = 18 // Total number of images to display
    @ObservedObject var arViewModel: ARViewModel
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(1...imageCount, id: \.self) { index in
                    NavigationLink(destination: ARPlacementView(arViewModel: arViewModel, selectedImageIndex: index)) {
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
