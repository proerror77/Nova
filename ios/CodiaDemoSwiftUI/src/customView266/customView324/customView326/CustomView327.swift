//
//  CustomView327.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView327: View {
    @State public var text182Text: String = "Liam"
    @State public var text183Text: String = "Hello, how are you bro~"
    @State public var text184Text: String = "09:41 PM"
    @State public var image217Path: String = "image217_41024"
    @State public var text185Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: -41) {
            CustomView328(
                text182Text: text182Text,
                text183Text: text183Text)
                .frame(width: 161, height: 46)
            CustomView329(
                text184Text: text184Text,
                image217Path: image217Path,
                text185Text: text185Text)
                .frame(width: 161)
        }
        .padding(EdgeInsets(top: 13, leading: 0, bottom: 10, trailing: 0))
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 72, alignment: .top)
    }
}

struct CustomView327_Previews: PreviewProvider {
    static var previews: some View {
        CustomView327()
    }
}
