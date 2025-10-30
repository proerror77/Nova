//
//  CustomView691.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView691: View {
    @State public var text329Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text(text329Text)
                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.54, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 14))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 125, alignment: .trailing)
    }
}

struct CustomView691_Previews: PreviewProvider {
    static var previews: some View {
        CustomView691()
    }
}
