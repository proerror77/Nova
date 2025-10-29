//
//  CustomView359.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView359: View {
    @State public var image233Path: String = "image233_41121"
    @State public var text198Text: String = "Mobile phone contacts"
    var body: some View {
        HStack(alignment: .center, spacing: 23) {
            Image(image233Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 19, height: 20, alignment: .topLeading)
            Text(text198Text)
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView359_Previews: PreviewProvider {
    static var previews: some View {
        CustomView359()
    }
}
