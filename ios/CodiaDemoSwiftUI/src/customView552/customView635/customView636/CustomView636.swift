//
//  CustomView636.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView636: View {
    @State public var image442Path: String = "image442_42083"
    @State public var text302Text: String = "1"
    @State public var text303Text: String = "Lucy Liu"
    @State public var text304Text: String = "Morgan Stanley"
    @State public var text305Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView637(
                image442Path: image442Path,
                text302Text: text302Text,
                text303Text: text303Text,
                text304Text: text304Text,
                text305Text: text305Text)
                .frame(width: 309, height: 389)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView636_Previews: PreviewProvider {
    static var previews: some View {
        CustomView636()
    }
}
