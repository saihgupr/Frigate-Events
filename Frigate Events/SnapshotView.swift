import SwiftUI

struct SnapshotView: View {
    let imageUrl: URL
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack {
                RemoteImage(url: imageUrl) {
                    ProgressView()
                        .scaleEffect(1.5)
                } content: { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.black)
            .navigationTitle("Snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

struct SnapshotView_Previews: PreviewProvider {
    static var previews: some View {
        if let url = URL(string: "https://example.com/snapshot.jpg") {
            SnapshotView(imageUrl: url)
        } else {
            Text("Invalid URL for preview")
        }
    }
}
