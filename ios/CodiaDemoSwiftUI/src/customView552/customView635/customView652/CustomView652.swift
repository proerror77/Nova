//
//  CustomView652.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView652: View {
    @State public var image454Path: String = "image454_42123"
    @State public var text310Text: String = "3"
    @State public var text311Text: String = "Lucy Liu"
    @State public var text312Text: String = "Morgan Stanley"
    @State public var text313Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView653(
                image454Path: image454Path,
                text310Text: text310Text,
                text311Text: text311Text,
                text312Text: text312Text,
                text313Text: text313Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 312, height: 392, alignment: .topLeading)
    }
}

struct CustomView652_Previews: PreviewProvider {
    static var previews: some View {
        CustomView652()
    }
}
