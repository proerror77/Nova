//
//  CustomView694.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView694: View {
    @State public var image484Path: String = "image484_42224"
    @State public var text330Text: String = "3"
    @State public var text331Text: String = "Lucy Liu"
    @State public var text332Text: String = "Morgan Stanley"
    @State public var text333Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView695(
                image484Path: image484Path,
                text330Text: text330Text,
                text331Text: text331Text,
                text332Text: text332Text,
                text333Text: text333Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView694_Previews: PreviewProvider {
    static var previews: some View {
        CustomView694()
    }
}
