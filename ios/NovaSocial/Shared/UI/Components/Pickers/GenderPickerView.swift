import SwiftUI

struct GenderPickerView: View {
    @Binding var selectedGender: Gender
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            List(Gender.selectableCases, id: \.self) { gender in
                Button(action: {
                    selectedGender = gender
                    isPresented = false
                }) {
                    HStack {
                        Text(gender.displayName)
                            .foregroundColor(.black)
                        Spacer()
                        if selectedGender == gender {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Select Gender")
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
