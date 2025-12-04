import SwiftUI

struct LocationPickerView: View {
    @Binding var selectedLocation: String
    @Binding var isPresented: Bool

    let locations = ["China", "United States", "United Kingdom", "Japan", "South Korea", "Taiwan", "Hong Kong", "Singapore", "Other"]

    var body: some View {
        NavigationView {
            List(locations, id: \.self) { location in
                Button(action: {
                    selectedLocation = location
                    isPresented = false
                }) {
                    HStack {
                        Text(location)
                            .foregroundColor(.black)
                        Spacer()
                        if selectedLocation == location {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}
