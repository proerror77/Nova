//
//  CustomView93.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView93: View {
    @State public var image79Path: String = "image79_4464"
    @State public var text61Text: String = "2293"
    var body: some View {
        HStack(alignment: .top, spacing: 3) {
            Image(image79Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 9, height: 8, alignment: .topLeading)
            Text(text61Text)
                .foregroundColor(Color(red: 0.45, green: 0.44, blue: 0.44, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 7))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView93_Previews: PreviewProvider {
    static var previews: some View {
        CustomView93()
    }
}
