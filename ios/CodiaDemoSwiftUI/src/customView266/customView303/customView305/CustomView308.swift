//
//  CustomView308.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView308: View {
    @State public var text172Text: String = "09:41 PM"
    @State public var image211Path: String = "image211_4982"
    @State public var text173Text: String = "1"
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(text172Text)
                .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 13))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            CustomView309(
                image211Path: image211Path,
                text173Text: text173Text)
                .frame(width: 17, height: 20)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 161, alignment: .leading)
    }
}

struct CustomView308_Previews: PreviewProvider {
    static var previews: some View {
        CustomView308()
    }
}
