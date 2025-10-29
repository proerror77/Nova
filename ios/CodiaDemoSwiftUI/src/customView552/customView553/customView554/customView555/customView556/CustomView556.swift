//
//  CustomView556.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView556: View {
    @State public var image382Path: String = "image382_41881"
    @State public var text262Text: String = "1"
    @State public var text263Text: String = "Lucy Liu"
    @State public var text264Text: String = "Morgan Stanley"
    @State public var text265Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image382Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView557(text262Text: text262Text)
                .frame(width: 35, height: 35)
            CustomView559(
                text263Text: text263Text,
                text264Text: text264Text)
                .frame(width: 99, height: 38)
            CustomView560(text265Text: text265Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView556_Previews: PreviewProvider {
    static var previews: some View {
        CustomView556()
    }
}
