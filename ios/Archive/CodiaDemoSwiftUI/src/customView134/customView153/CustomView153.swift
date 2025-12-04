//
//  CustomView153.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView153: View {
    @State public var image114Path: String = "image114_4617"
    @State public var text87Text: String = "Devices"
    @State public var image115Path: String = "image115_4627"
    var body: some View {
        HStack(alignment: .center) {
            Image(image114Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 21.891, alignment: .leading)
            CustomView154(
                text87Text: text87Text,
                image115Path: image115Path)
                .frame(width: 319)
        }
        .frame(width: 340.891, height: 60, alignment: .topLeading)
    }
}

struct CustomView153_Previews: PreviewProvider {
    static var previews: some View {
        CustomView153()
    }
}
