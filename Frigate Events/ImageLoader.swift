import SwiftUI

struct RemoteImage<Content: View, Placeholder: View>: View {
    let url: URL
    let placeholder: () -> Placeholder
    let content: (Image) -> Content
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var error: Error?
    
    init(url: URL, @ViewBuilder placeholder: @escaping () -> Placeholder, @ViewBuilder content: @escaping (Image) -> Content) {
        self.url = url
        self.placeholder = placeholder
        self.content = content
    }
    
    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else if isLoading {
                placeholder()
            } else {
                placeholder()
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard image == nil else { return }
        
        isLoading = true
        error = nil
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.error = error
                    return
                }
                
                guard let data = data, let uiImage = UIImage(data: data) else {
                    self.error = NSError(domain: "ImageLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
                    return
                }
                
                self.image = uiImage
            }
        }.resume()
    }
}
