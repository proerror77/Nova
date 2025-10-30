//
//  CustomView148.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView148: View {
    @State public var image112Path: String = "image112_4604"
    @State public var text86Text: String = "Alias Accounts"
    @State public var image113Path: String = "image113_4614"
    var body: some View {
        HStack(alignment: .center) {
            Image(image112Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 21.891, alignment: .leading)
            CustomView149(
                text86Text: text86Text,
                image113Path: image113Path)
                .frame(width: 319)
        }
        .frame(width: 340.891, height: 60, alignment: .topLeading)
    }
}

struct CustomView148_Previews: PreviewProvider {
    static var previews: some View {
        CustomView148()
    }
}
