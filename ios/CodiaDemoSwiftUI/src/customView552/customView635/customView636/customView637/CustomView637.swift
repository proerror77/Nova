//
//  CustomView637.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView637: View {
    @State public var image442Path: String = "image442_42083"
    @State public var text302Text: String = "1"
    @State public var text303Text: String = "Lucy Liu"
    @State public var text304Text: String = "Morgan Stanley"
    @State public var text305Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView638(
                image442Path: image442Path,
                text302Text: text302Text,
                text303Text: text303Text,
                text304Text: text304Text,
                text305Text: text305Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView637_Previews: PreviewProvider {
    static var previews: some View {
        CustomView637()
    }
}
