//
//  CustomView668.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView668: View {
    @State public var image466Path: String = "image466_42163"
    @State public var text318Text: String = "5"
    @State public var text319Text: String = "Lucy Liu"
    @State public var text320Text: String = "Morgan Stanley"
    @State public var text321Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView669(
                image466Path: image466Path,
                text318Text: text318Text,
                text319Text: text319Text,
                text320Text: text320Text,
                text321Text: text321Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 311, height: 392, alignment: .topLeading)
    }
}

struct CustomView668_Previews: PreviewProvider {
    static var previews: some View {
        CustomView668()
    }
}
