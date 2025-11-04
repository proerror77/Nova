//
//  CustomView654.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView654: View {
    @State public var image454Path: String = "image454_42123"
    @State public var text310Text: String = "3"
    @State public var text311Text: String = "Lucy Liu"
    @State public var text312Text: String = "Morgan Stanley"
    @State public var text313Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image454Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView655(text310Text: text310Text)
                .frame(width: 35, height: 35)
            CustomView657(
                text311Text: text311Text,
                text312Text: text312Text)
                .frame(width: 99, height: 38)
            CustomView658(text313Text: text313Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView654_Previews: PreviewProvider {
    static var previews: some View {
        CustomView654()
    }
}
