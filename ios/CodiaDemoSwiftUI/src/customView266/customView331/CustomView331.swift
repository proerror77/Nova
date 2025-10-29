//
//  CustomView331.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView331: View {
    @State public var image218Path: String = "image218_41029"
    @State public var text186Text: String = "Liam"
    @State public var text187Text: String = "Hello, how are you bro~"
    @State public var text188Text: String = "09:41 PM"
    @State public var image219Path: String = "image219_41038"
    @State public var text189Text: String = "1"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                .frame(width: 393, height: 80)
            CustomView333(
                image218Path: image218Path,
                text186Text: text186Text,
                text187Text: text187Text,
                text188Text: text188Text,
                image219Path: image219Path,
                text189Text: text189Text)
                .frame(width: 356, height: 72)
                .offset(x: 22, y: 4)
        }
        .frame(width: 393, height: 80, alignment: .topLeading)
    }
}

struct CustomView331_Previews: PreviewProvider {
    static var previews: some View {
        CustomView331()
    }
}
