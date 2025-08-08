
import SwiftUI

struct SnapshotView: View {
    let imageUrl: URL

    var body: some View {
        RemoteImage(url: imageUrl) {
            ProgressView()
        } content: { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

struct SnapshotView_Previews: PreviewProvider {
    static var previews: some View {
        SnapshotView(imageUrl: URL(string: "https://via.placeholder.com/1920x1080.png?text=Full+Size+Snapshot")!)
    }
}
