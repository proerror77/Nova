//
//  CustomView101.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView101: View {
    @State public var image83Path: String = "image83_4487"
    @State public var text66Text: String = "2293"
    var body: some View {
        HStack(alignment: .top, spacing: 3) {
            Image(image83Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 9, height: 8, alignment: .topLeading)
            Text(text66Text)
                .foregroundColor(Color(red: 0.45, green: 0.44, blue: 0.44, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 7))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView101_Previews: PreviewProvider {
    static var previews: some View {
        CustomView101()
    }
}
