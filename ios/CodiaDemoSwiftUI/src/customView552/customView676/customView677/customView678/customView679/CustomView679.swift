//
//  CustomView679.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView679: View {
    @State public var image472Path: String = "image472_42184"
    @State public var text322Text: String = "1"
    @State public var text323Text: String = "Lucy Liu"
    @State public var text324Text: String = "Morgan Stanley"
    @State public var text325Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image472Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView680(text322Text: text322Text)
                .frame(width: 35, height: 35)
            CustomView682(
                text323Text: text323Text,
                text324Text: text324Text)
                .frame(width: 99, height: 38)
            CustomView683(text325Text: text325Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView679_Previews: PreviewProvider {
    static var previews: some View {
        CustomView679()
    }
}
