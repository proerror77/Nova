//
//  CustomView259.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView259: View {
    @State public var text145Text: String = "Bruce Li"
    @State public var image189Path: String = "image189_I490141875"
    @State public var image190Path: String = "image190_4902"
    var body: some View {
        HStack(alignment: .center, spacing: 243) {
            CustomView260(
                text145Text: text145Text,
                image189Path: image189Path)
                .frame(width: 100, height: 16)
            Image(image190Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21.999, height: 20.99, alignment: .topLeading)
        }
        .frame(width: 365, height: 20.99, alignment: .topLeading)
    }
}

struct CustomView259_Previews: PreviewProvider {
    static var previews: some View {
        CustomView259()
    }
}
