//
//  CustomView291.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView291: View {
    @State public var image206Path: String = "image206_I49684957"
    @State public var text162Text: String = "Liam"
    @State public var text163Text: String = "Hello, how are you bro~"
    @State public var text164Text: String = "09:41 PM"
    @State public var image207Path: String = "image207_I49684966"
    @State public var text165Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(image206Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView292(
                text162Text: text162Text,
                text163Text: text163Text,
                text164Text: text164Text,
                image207Path: image207Path,
                text165Text: text165Text)
                .frame(height: 72)
        }
        .frame(width: 356, height: 72, alignment: .topLeading)
    }
}

struct CustomView291_Previews: PreviewProvider {
    static var previews: some View {
        CustomView291()
    }
}
