//
//  CustomView322.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView322: View {
    @State public var text180Text: String = "09:41 PM"
    @State public var image215Path: String = "image215_41010"
    @State public var text181Text: String = "1"
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(text180Text)
                .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 13))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
            CustomView323(
                image215Path: image215Path,
                text181Text: text181Text)
                .frame(width: 17, height: 20)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 161, alignment: .leading)
    }
}

struct CustomView322_Previews: PreviewProvider {
    static var previews: some View {
        CustomView322()
    }
}
