//
//  CustomView119.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView119: View {
    @State public var text73Text: String = "Received likes and collected "
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(text73Text)
                .foregroundColor(Color(red: 0.26, green: 0.26, blue: 0.26, opacity: 1.00))
                .font(.custom("HelveticaNeue-Bold", size: 15.5))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct CustomView119_Previews: PreviewProvider {
    static var previews: some View {
        CustomView119()
    }
}
