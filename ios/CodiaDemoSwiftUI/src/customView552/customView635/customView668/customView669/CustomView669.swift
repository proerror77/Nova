//
//  CustomView669.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView669: View {
    @State public var image466Path: String = "image466_42163"
    @State public var text318Text: String = "5"
    @State public var text319Text: String = "Lucy Liu"
    @State public var text320Text: String = "Morgan Stanley"
    @State public var text321Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView670(
                image466Path: image466Path,
                text318Text: text318Text,
                text319Text: text319Text,
                text320Text: text320Text,
                text321Text: text321Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView669_Previews: PreviewProvider {
    static var previews: some View {
        CustomView669()
    }
}
