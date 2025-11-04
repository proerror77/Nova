//
//  CustomView190.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView190: View {
    @State public var text100Text: String = "Bruce Li"
    @State public var image134Path: String = "image134_I471441875"
    @State public var image135Path: String = "image135_4715"
    var body: some View {
        HStack(alignment: .center, spacing: 243) {
            CustomView191(
                text100Text: text100Text,
                image134Path: image134Path)
                .frame(width: 100, height: 16)
            Image(image135Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21.999, height: 20.99, alignment: .topLeading)
        }
        .frame(width: 365, height: 20.99, alignment: .topLeading)
    }
}

struct CustomView190_Previews: PreviewProvider {
    static var previews: some View {
        CustomView190()
    }
}
