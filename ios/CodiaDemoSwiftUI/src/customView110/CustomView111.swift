//
//  CustomView111.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView111: View {
    @State public var text71Text: String = "Bruce Li"
    @State public var image90Path: String = "image90_I451641875"
    @State public var image91Path: String = "image91_4517"
    var body: some View {
        HStack(alignment: .center, spacing: 243) {
            CustomView112(
                text71Text: text71Text,
                image90Path: image90Path)
                .frame(width: 100, height: 16)
            Image(image91Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21.999, height: 20.99, alignment: .topLeading)
        }
        .frame(width: 365, height: 20.99, alignment: .topLeading)
    }
}

struct CustomView111_Previews: PreviewProvider {
    static var previews: some View {
        CustomView111()
    }
}
