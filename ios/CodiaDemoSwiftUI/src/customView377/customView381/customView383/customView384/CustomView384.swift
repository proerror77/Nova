//
//  CustomView384.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView384: View {
    @State public var text206Text: String = "All contacts"
    @State public var text207Text: String = "4"
    @State public var image251Path: String = "image251_41288"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView385(
                text206Text: text206Text,
                text207Text: text207Text,
                image251Path: image251Path)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 319, alignment: .leading)
    }
}

struct CustomView384_Previews: PreviewProvider {
    static var previews: some View {
        CustomView384()
    }
}
