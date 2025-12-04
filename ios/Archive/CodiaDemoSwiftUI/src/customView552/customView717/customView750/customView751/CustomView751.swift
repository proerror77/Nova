//
//  CustomView751.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView751: View {
    @State public var image526Path: String = "image526_42365"
    @State public var text358Text: String = "5"
    @State public var text359Text: String = "Lucy Liu"
    @State public var text360Text: String = "Morgan Stanley"
    @State public var text361Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView752(
                image526Path: image526Path,
                text358Text: text358Text,
                text359Text: text359Text,
                text360Text: text360Text,
                text361Text: text361Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView751_Previews: PreviewProvider {
    static var previews: some View {
        CustomView751()
    }
}
