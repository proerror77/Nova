//
//  CustomView326.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView326: View {
    @State public var image216Path: String = "image216_41015"
    @State public var text182Text: String = "Liam"
    @State public var text183Text: String = "Hello, how are you bro~"
    @State public var text184Text: String = "09:41 PM"
    @State public var image217Path: String = "image217_41024"
    @State public var text185Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(image216Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView327(
                text182Text: text182Text,
                text183Text: text183Text,
                text184Text: text184Text,
                image217Path: image217Path,
                text185Text: text185Text)
                .frame(height: 72)
        }
        .frame(width: 356, height: 72, alignment: .topLeading)
    }
}

struct CustomView326_Previews: PreviewProvider {
    static var previews: some View {
        CustomView326()
    }
}
