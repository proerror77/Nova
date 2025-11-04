//
//  CustomView289.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView289: View {
    @State public var image206Path: String = "image206_I49684957"
    @State public var text162Text: String = "Liam"
    @State public var text163Text: String = "Hello, how are you bro~"
    @State public var text164Text: String = "09:41 PM"
    @State public var image207Path: String = "image207_I49684966"
    @State public var text165Text: String = "1"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                .frame(width: 393, height: 80)
            CustomView291(
                image206Path: image206Path,
                text162Text: text162Text,
                text163Text: text163Text,
                text164Text: text164Text,
                image207Path: image207Path,
                text165Text: text165Text)
                .frame(width: 356, height: 72)
                .offset(x: 22, y: 4)
        }
        .frame(width: 393, height: 80, alignment: .topLeading)
    }
}

struct CustomView289_Previews: PreviewProvider {
    static var previews: some View {
        CustomView289()
    }
}
