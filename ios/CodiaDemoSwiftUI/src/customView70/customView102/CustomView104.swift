//
//  CustomView104.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView104: View {
    @State public var text68Text: String = "Share profile"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(text68Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 15))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(EdgeInsets(top: 8, leading: 34, bottom: 8, trailing: 34))
        .frame(width: 157, height: 35, alignment: .top)
        .background(Color(red: 0.39, green: 0.39, blue: 0.39, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct CustomView104_Previews: PreviewProvider {
    static var previews: some View {
        CustomView104()
    }
}
