import SwiftUI

struct AppCardView: View {
    var imageName: String
    var appName: String
    var appDescription: String
    var appURL: String

    var body: some View {
        HStack {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .cornerRadius(7)

            VStack(alignment: .leading) {
                Text(appName)
                    .font(.title3)
                    .foregroundColor(Color(white: 0.6))
                Text(appDescription)
                    .font(.caption)
                    .foregroundColor(Color(white: 0.6))
            }

            Spacer()

            Button(action: {
                if let url = URL(string: appURL) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Try")
                    .font(.headline)
                    .padding()
                    .frame(minWidth: 100)
                    .background(LinearGradient(
                        gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.blue]),
                        startPoint: .top, endPoint: .bottom
                    ))
                    .foregroundColor(.white)
                    .cornerRadius(11)
                    .shadow(color: .black.opacity(0.3), radius: 6, x: 3, y: 3)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.8), lineWidth: 1))
            }
        }
    }
}
