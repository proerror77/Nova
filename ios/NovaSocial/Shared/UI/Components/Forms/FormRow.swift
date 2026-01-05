import SwiftUI

struct FormRow: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .font(Font.custom("SFProDisplay-Regular", size: 15.f))
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                .frame(width: 100, alignment: .leading)

            TextField("", text: $text)
                .font(Font.custom("SFProDisplay-Regular", size: 15.f))
                .foregroundColor(.black)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
