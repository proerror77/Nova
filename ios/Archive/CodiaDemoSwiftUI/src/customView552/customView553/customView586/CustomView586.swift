//
//  CustomView586.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView586: View {
    @State public var image406Path: String = "image406_41961"
    @State public var text278Text: String = "5"
    @State public var text279Text: String = "Lucy Liu"
    @State public var text280Text: String = "Morgan Stanley"
    @State public var text281Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView587(
                image406Path: image406Path,
                text278Text: text278Text,
                text279Text: text279Text,
                text280Text: text280Text,
                text281Text: text281Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 311, height: 392, alignment: .topLeading)
    }
}

struct CustomView586_Previews: PreviewProvider {
    static var previews: some View {
        CustomView586()
    }
}
