import SwiftUI

struct DateOfBirthPickerView: View {
    @Binding var dateString: String
    @Binding var isPresented: Bool
    @State private var selectedDate = Date()

    var body: some View {
        NavigationView {
            VStack {
                DatePicker(
                    "Date of Birth",
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding()

                Spacer()
            }
            .navigationTitle("Date of Birth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        dateString = formatter.string(from: selectedDate)
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            if !dateString.isEmpty {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                if let date = formatter.date(from: dateString) {
                    selectedDate = date
                }
            }
        }
    }
}
