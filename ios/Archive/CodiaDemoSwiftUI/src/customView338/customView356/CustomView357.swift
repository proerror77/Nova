//
//  CustomView357.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView357: View {
    @State public var image232Path: String = "image232_41114"
    @State public var text197Text: String = "Add a contact"
    var body: some View {
        HStack(alignment: .top, spacing: 23) {
            Image(image232Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 19, height: 21, alignment: .topLeading)
            Text(text197Text)
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView357_Previews: PreviewProvider {
    static var previews: some View {
        CustomView357()
    }
}
