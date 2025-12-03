import SwiftUI

struct FormRow: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                .frame(width: 100, alignment: .leading)

            TextField("", text: $text)
                .font(.system(size: 15))
                .foregroundColor(.black)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
