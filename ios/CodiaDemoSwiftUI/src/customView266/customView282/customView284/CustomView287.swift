//
//  CustomView287.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView287: View {
    @State public var text160Text: String = "09:41 PM"
    @State public var image205Path: String = "image205_4966"
    @State public var text161Text: String = "1"
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(text160Text)
                .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 13))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            CustomView288(
                image205Path: image205Path,
                text161Text: text161Text)
                .frame(width: 17, height: 20)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 161, alignment: .leading)
    }
}

struct CustomView287_Previews: PreviewProvider {
    static var previews: some View {
        CustomView287()
    }
}
