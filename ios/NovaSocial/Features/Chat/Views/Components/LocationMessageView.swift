import SwiftUI
import MapKit
import CoreLocation

/// View for displaying location messages in chat
struct LocationMessageView: View {
    let location: CLLocationCoordinate2D

    var body: some View {
        let region = MKCoordinateRegion(
            center: location,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        VStack(spacing: 4) {
            Map(initialPosition: .region(region)) { }
                .frame(width: 180, height: 120)
                .cornerRadius(12)
                .disabled(true)
            Text("My Location")
                .font(.system(size: 12))
                .foregroundColor(DesignTokens.textPrimary)
        }
        .padding(8)
        .background(DesignTokens.chatBubbleOther)
        .cornerRadius(12)
    }
}
