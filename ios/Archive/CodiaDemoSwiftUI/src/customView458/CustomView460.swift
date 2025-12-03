//
//  CustomView460.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView460: View {
    @State public var text232Text: String = "Photos"
    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            Rectangle()
                .fill(Color(red: 0.85, green: 0.85, blue: 0.85, opacity: 1.00))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(height: 60)
            Text(text232Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 16))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(width: 60, height: 83, alignment: .top)
    }
}

struct CustomView460_Previews: PreviewProvider {
    static var previews: some View {
        CustomView460()
    }
}
