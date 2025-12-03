//
//  CustomView605.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView605: View {
    @State public var image418Path: String = "image418_42002"
    @State public var text286Text: String = "2"
    @State public var text287Text: String = "Lucy Liu"
    @State public var text288Text: String = "Morgan Stanley"
    @State public var text289Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image418Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView606(text286Text: text286Text)
                .frame(width: 35, height: 35)
            CustomView608(
                text287Text: text287Text,
                text288Text: text288Text)
                .frame(width: 99, height: 38)
            CustomView609(text289Text: text289Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView605_Previews: PreviewProvider {
    static var previews: some View {
        CustomView605()
    }
}
