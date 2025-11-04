//
//  CustomView334.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView334: View {
    @State public var text186Text: String = "Liam"
    @State public var text187Text: String = "Hello, how are you bro~"
    @State public var text188Text: String = "09:41 PM"
    @State public var image219Path: String = "image219_41038"
    @State public var text189Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: -41) {
            CustomView335(
                text186Text: text186Text,
                text187Text: text187Text)
                .frame(width: 161, height: 46)
            CustomView336(
                text188Text: text188Text,
                image219Path: image219Path,
                text189Text: text189Text)
                .frame(width: 161)
        }
        .padding(EdgeInsets(top: 13, leading: 0, bottom: 10, trailing: 0))
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 72, alignment: .top)
    }
}

struct CustomView334_Previews: PreviewProvider {
    static var previews: some View {
        CustomView334()
    }
}
