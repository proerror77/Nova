//
//  CustomView333.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView333: View {
    @State public var image218Path: String = "image218_41029"
    @State public var text186Text: String = "Liam"
    @State public var text187Text: String = "Hello, how are you bro~"
    @State public var text188Text: String = "09:41 PM"
    @State public var image219Path: String = "image219_41038"
    @State public var text189Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(image218Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView334(
                text186Text: text186Text,
                text187Text: text187Text,
                text188Text: text188Text,
                image219Path: image219Path,
                text189Text: text189Text)
                .frame(height: 72)
        }
        .frame(width: 356, height: 72, alignment: .topLeading)
    }
}

struct CustomView333_Previews: PreviewProvider {
    static var previews: some View {
        CustomView333()
    }
}
