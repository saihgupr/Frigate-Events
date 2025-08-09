import SwiftUI
import Combine

class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    private let url: URL
    private var cancellable: AnyCancellable?

    init(url: URL) {
        self.url = url
    }

    deinit {
        cancel()
    }

    func load() {
        cancellable = URLSession.shared.dataTaskPublisher(for: url)
            .map { UIImage(data: $0.data) }
            .replaceError(with: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.image = $0 }
    }

    func cancel() {
        cancellable?.cancel()
    }
}

struct RemoteImage<Placeholder: View, Content: View>: View {
    @StateObject private var loader: ImageLoader
    private let placeholder: Placeholder
    private let content: (Image) -> Content

    init(url: URL, @ViewBuilder placeholder: () -> Placeholder, @ViewBuilder content: @escaping (Image) -> Content) {
        _loader = StateObject(wrappedValue: ImageLoader(url: url))
        self.placeholder = placeholder()
        self.content = content
    }

    var body: some View {
        Group {
            if let uiImage = loader.image {
                content(Image(uiImage: uiImage))
            } else {
                placeholder
            }
        }
        .onAppear(perform: loader.load)
    }
}
