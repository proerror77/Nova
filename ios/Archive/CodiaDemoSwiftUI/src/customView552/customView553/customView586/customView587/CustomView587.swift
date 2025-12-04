//
//  CustomView587.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView587: View {
    @State public var image406Path: String = "image406_41961"
    @State public var text278Text: String = "5"
    @State public var text279Text: String = "Lucy Liu"
    @State public var text280Text: String = "Morgan Stanley"
    @State public var text281Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView588(
                image406Path: image406Path,
                text278Text: text278Text,
                text279Text: text279Text,
                text280Text: text280Text,
                text281Text: text281Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView587_Previews: PreviewProvider {
    static var previews: some View {
        CustomView587()
    }
}
