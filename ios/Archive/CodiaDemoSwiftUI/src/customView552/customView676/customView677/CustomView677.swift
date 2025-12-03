//
//  CustomView677.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView677: View {
    @State public var image472Path: String = "image472_42184"
    @State public var text322Text: String = "1"
    @State public var text323Text: String = "Lucy Liu"
    @State public var text324Text: String = "Morgan Stanley"
    @State public var text325Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView678(
                image472Path: image472Path,
                text322Text: text322Text,
                text323Text: text323Text,
                text324Text: text324Text,
                text325Text: text325Text)
                .frame(width: 309, height: 389)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView677_Previews: PreviewProvider {
    static var previews: some View {
        CustomView677()
    }
}
