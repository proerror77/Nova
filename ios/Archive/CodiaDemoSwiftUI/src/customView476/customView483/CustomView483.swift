//
//  CustomView483.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView483: View {
    @State public var image302Path: String = "image302_41532"
    @State public var text240Text: String = "Uh-huh..."
    @State public var image303Path: String = "image303_41544"
    @State public var text241Text: String = "miss you"
    @State public var image304Path: String = "image304_41549"
    @State public var text242Text: String = "Hello, how are you bro~"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image302Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 111, height: 46, alignment: .topLeading)
                .offset(x: 202, y: 178)
            CustomView484(
                text240Text: text240Text,
                image303Path: image303Path)
                .frame(width: 167, height: 50)
                .offset(x: 202, y: 122)
            CustomView487(text241Text: text241Text)
                .frame(width: 116, height: 46)
                .offset(x: 56, y: 58)
            CustomView489(
                image304Path: image304Path,
                text242Text: text242Text)
                .frame(width: 283, height: 50)
        }
        .frame(width: 369, height: 224, alignment: .topLeading)
    }
}

struct CustomView483_Previews: PreviewProvider {
    static var previews: some View {
        CustomView483()
    }
}
