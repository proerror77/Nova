//
//  CustomView563.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView563: View {
    @State public var image388Path: String = "image388_41901"
    @State public var text266Text: String = "2"
    @State public var text267Text: String = "Lucy Liu"
    @State public var text268Text: String = "Morgan Stanley"
    @State public var text269Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView564(
                image388Path: image388Path,
                text266Text: text266Text,
                text267Text: text267Text,
                text268Text: text268Text,
                text269Text: text269Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView563_Previews: PreviewProvider {
    static var previews: some View {
        CustomView563()
    }
}
