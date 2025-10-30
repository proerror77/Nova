//
//  CustomView130.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView130: View {
    @State public var text81Text: String = "Bruce Li"
    @State public var image100Path: String = "image100_I456341875"
    @State public var image101Path: String = "image101_4564"
    var body: some View {
        HStack(alignment: .center, spacing: 243) {
            CustomView131(
                text81Text: text81Text,
                image100Path: image100Path)
                .frame(width: 100, height: 16)
            Image(image101Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21.999, height: 20.99, alignment: .topLeading)
        }
        .frame(width: 365, height: 20.99, alignment: .topLeading)
    }
}

struct CustomView130_Previews: PreviewProvider {
    static var previews: some View {
        CustomView130()
    }
}
