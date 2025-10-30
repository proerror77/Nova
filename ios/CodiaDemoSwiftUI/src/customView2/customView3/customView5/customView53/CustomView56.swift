//
//  CustomView56.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView56: View {
    @State public var image35Path: String = "image35_4291"
    @State public var text26Text: String = "93"
    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(image35Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18.261, height: 15.476, alignment: .topLeading)
            Text(text26Text)
                .foregroundColor(Color(red: 0.56, green: 0.56, blue: 0.56, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 14))
                .lineLimit(1)
                .frame(width: 18.246, height: 18.654, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .frame(width: 40.43, height: 18.654, alignment: .topLeading)
    }
}

struct CustomView56_Previews: PreviewProvider {
    static var previews: some View {
        CustomView56()
    }
}
