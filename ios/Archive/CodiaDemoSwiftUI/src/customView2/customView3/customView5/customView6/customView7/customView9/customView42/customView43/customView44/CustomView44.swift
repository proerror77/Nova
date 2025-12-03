//
//  CustomView44.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView44: View {
    @State public var image25Path: String = "image25_I426841961"
    @State public var text19Text: String = "5"
    @State public var text20Text: String = "Lucy Liu"
    @State public var text21Text: String = "Morgan Stanley"
    @State public var text22Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image25Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView45(text19Text: text19Text)
                .frame(width: 35, height: 35)
            CustomView47(
                text20Text: text20Text,
                text21Text: text21Text)
                .frame(width: 99, height: 38)
            CustomView48(text22Text: text22Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView44_Previews: PreviewProvider {
    static var previews: some View {
        CustomView44()
    }
}
