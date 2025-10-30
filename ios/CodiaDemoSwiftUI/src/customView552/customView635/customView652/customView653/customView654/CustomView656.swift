//
//  CustomView656.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView656: View {
    @State public var text310Text: String = "3"
    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Text(text310Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 20))
                .lineLimit(1)
                .frame(width: 11, height: 26, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView656_Previews: PreviewProvider {
    static var previews: some View {
        CustomView656()
    }
}
