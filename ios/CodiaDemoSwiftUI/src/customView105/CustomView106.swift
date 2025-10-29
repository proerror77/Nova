//
//  CustomView106.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView106: View {
    @State public var text69Text: String = "Bruce Li"
    @State public var image85Path: String = "image85_I450441875"
    @State public var image86Path: String = "image86_4505"
    var body: some View {
        HStack(alignment: .center, spacing: 243) {
            CustomView107(
                text69Text: text69Text,
                image85Path: image85Path)
                .frame(width: 100, height: 16)
            Image(image86Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21.999, height: 20.99, alignment: .topLeading)
        }
        .frame(width: 365, height: 20.99, alignment: .topLeading)
    }
}

struct CustomView106_Previews: PreviewProvider {
    static var previews: some View {
        CustomView106()
    }
}
