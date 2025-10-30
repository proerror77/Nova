//
//  CustomView562.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView562: View {
    @State public var image388Path: String = "image388_41901"
    @State public var text266Text: String = "2"
    @State public var text267Text: String = "Lucy Liu"
    @State public var text268Text: String = "Morgan Stanley"
    @State public var text269Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView563(
                image388Path: image388Path,
                text266Text: text266Text,
                text267Text: text267Text,
                text268Text: text268Text,
                text269Text: text269Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 311, height: 392, alignment: .topLeading)
    }
}

struct CustomView562_Previews: PreviewProvider {
    static var previews: some View {
        CustomView562()
    }
}
