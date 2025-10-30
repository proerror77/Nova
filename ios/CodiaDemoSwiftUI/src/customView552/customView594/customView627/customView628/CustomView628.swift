//
//  CustomView628.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView628: View {
    @State public var image436Path: String = "image436_42062"
    @State public var text298Text: String = "5"
    @State public var text299Text: String = "Lucy Liu"
    @State public var text300Text: String = "Morgan Stanley"
    @State public var text301Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView629(
                image436Path: image436Path,
                text298Text: text298Text,
                text299Text: text299Text,
                text300Text: text300Text,
                text301Text: text301Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView628_Previews: PreviewProvider {
    static var previews: some View {
        CustomView628()
    }
}
