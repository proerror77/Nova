//
//  CustomView555.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView555: View {
    @State public var image382Path: String = "image382_41881"
    @State public var text262Text: String = "1"
    @State public var text263Text: String = "Lucy Liu"
    @State public var text264Text: String = "Morgan Stanley"
    @State public var text265Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView556(
                image382Path: image382Path,
                text262Text: text262Text,
                text263Text: text263Text,
                text264Text: text264Text,
                text265Text: text265Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView555_Previews: PreviewProvider {
    static var previews: some View {
        CustomView555()
    }
}
