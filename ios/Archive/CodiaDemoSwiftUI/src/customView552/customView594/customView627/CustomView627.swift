//
//  CustomView627.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView627: View {
    @State public var image436Path: String = "image436_42062"
    @State public var text298Text: String = "5"
    @State public var text299Text: String = "Lucy Liu"
    @State public var text300Text: String = "Morgan Stanley"
    @State public var text301Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView628(
                image436Path: image436Path,
                text298Text: text298Text,
                text299Text: text299Text,
                text300Text: text300Text,
                text301Text: text301Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 311, height: 392, alignment: .topLeading)
    }
}

struct CustomView627_Previews: PreviewProvider {
    static var previews: some View {
        CustomView627()
    }
}
