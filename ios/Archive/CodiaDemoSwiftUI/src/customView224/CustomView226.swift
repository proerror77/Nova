//
//  CustomView226.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView226: View {
    @State public var text120Text: String = "Bruce Li"
    @State public var image161Path: String = "image161_I480141875"
    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Text(text120Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 21))
                .lineLimit(1)
                .frame(width: 83, alignment: .leading)
                .multilineTextAlignment(.leading)
            Image(image161Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 5, alignment: .topLeading)
        }
        .frame(width: 100, height: 16, alignment: .top)
    }
}

struct CustomView226_Previews: PreviewProvider {
    static var previews: some View {
        CustomView226()
    }
}
