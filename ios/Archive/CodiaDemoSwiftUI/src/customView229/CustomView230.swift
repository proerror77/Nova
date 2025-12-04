//
//  CustomView230.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView230: View {
    @State public var text122Text: String = "Bruce Li"
    @State public var image166Path: String = "image166_I481341875"
    @State public var image167Path: String = "image167_4814"
    var body: some View {
        HStack(alignment: .center, spacing: 243) {
            CustomView231(
                text122Text: text122Text,
                image166Path: image166Path)
                .frame(width: 100, height: 16)
            Image(image167Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21.999, height: 20.99, alignment: .topLeading)
        }
        .frame(width: 365, height: 20.99, alignment: .topLeading)
    }
}

struct CustomView230_Previews: PreviewProvider {
    static var previews: some View {
        CustomView230()
    }
}
