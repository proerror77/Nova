//
//  CustomView324.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView324: View {
    @State public var image216Path: String = "image216_41015"
    @State public var text182Text: String = "Liam"
    @State public var text183Text: String = "Hello, how are you bro~"
    @State public var text184Text: String = "09:41 PM"
    @State public var image217Path: String = "image217_41024"
    @State public var text185Text: String = "1"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                .frame(width: 393, height: 80)
            CustomView326(
                image216Path: image216Path,
                text182Text: text182Text,
                text183Text: text183Text,
                text184Text: text184Text,
                image217Path: image217Path,
                text185Text: text185Text)
                .frame(width: 356, height: 72)
                .offset(x: 22, y: 4)
        }
        .frame(width: 393, height: 80, alignment: .topLeading)
    }
}

struct CustomView324_Previews: PreviewProvider {
    static var previews: some View {
        CustomView324()
    }
}
