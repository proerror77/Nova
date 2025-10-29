//
//  CustomView386.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView386: View {
    @State public var text206Text: String = "All contacts"
    @State public var text207Text: String = "4"
    @State public var image251Path: String = "image251_41288"
    var body: some View {
        HStack(alignment: .center, spacing: 173) {
            CustomView387(text206Text: text206Text)
            CustomView388(
                text207Text: text207Text,
                image251Path: image251Path)
                .frame(width: 24)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView386_Previews: PreviewProvider {
    static var previews: some View {
        CustomView386()
    }
}
