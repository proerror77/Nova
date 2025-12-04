//
//  CustomView588.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView588: View {
    @State public var image406Path: String = "image406_41961"
    @State public var text278Text: String = "5"
    @State public var text279Text: String = "Lucy Liu"
    @State public var text280Text: String = "Morgan Stanley"
    @State public var text281Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image406Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView589(text278Text: text278Text)
                .frame(width: 35, height: 35)
            CustomView591(
                text279Text: text279Text,
                text280Text: text280Text)
                .frame(width: 99, height: 38)
            CustomView592(text281Text: text281Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView588_Previews: PreviewProvider {
    static var previews: some View {
        CustomView588()
    }
}
