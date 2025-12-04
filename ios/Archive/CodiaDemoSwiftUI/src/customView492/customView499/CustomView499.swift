//
//  CustomView499.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView499: View {
    @State public var image310Path: String = "image310_41589"
    @State public var text245Text: String = "Uh-huh..."
    @State public var image311Path: String = "image311_41601"
    @State public var text246Text: String = "miss you"
    @State public var image312Path: String = "image312_41606"
    @State public var text247Text: String = "Hello, how are you bro~"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image310Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 111, height: 46, alignment: .topLeading)
                .offset(x: 202, y: 178)
            CustomView500(
                text245Text: text245Text,
                image311Path: image311Path)
                .frame(width: 167, height: 50)
                .offset(x: 202, y: 122)
            CustomView503(text246Text: text246Text)
                .frame(width: 116, height: 46)
                .offset(x: 56, y: 58)
            CustomView505(
                image312Path: image312Path,
                text247Text: text247Text)
                .frame(width: 283, height: 50)
        }
        .frame(width: 369, height: 224, alignment: .topLeading)
    }
}

struct CustomView499_Previews: PreviewProvider {
    static var previews: some View {
        CustomView499()
    }
}
