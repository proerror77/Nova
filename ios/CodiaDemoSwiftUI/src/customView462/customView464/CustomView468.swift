//
//  CustomView468.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView468: View {
    @State public var image290Path: String = "image290_41448"
    @State public var text234Text: String = "Drafts"
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Image(image290Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 13, height: 12.997, alignment: .topLeading)
            Text(text234Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 12.5))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView468_Previews: PreviewProvider {
    static var previews: some View {
        CustomView468()
    }
}
