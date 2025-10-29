//
//  CustomView670.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView670: View {
    @State public var image466Path: String = "image466_42163"
    @State public var text318Text: String = "5"
    @State public var text319Text: String = "Lucy Liu"
    @State public var text320Text: String = "Morgan Stanley"
    @State public var text321Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image466Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView671(text318Text: text318Text)
                .frame(width: 35, height: 35)
            CustomView673(
                text319Text: text319Text,
                text320Text: text320Text)
                .frame(width: 99, height: 38)
            CustomView674(text321Text: text321Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView670_Previews: PreviewProvider {
    static var previews: some View {
        CustomView670()
    }
}
