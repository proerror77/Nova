//
//  CustomView135.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView135: View {
    @State public var text83Text: String = "Bruce Li"
    @State public var image105Path: String = "image105_I457541875"
    @State public var image106Path: String = "image106_4576"
    var body: some View {
        HStack(alignment: .center, spacing: 243) {
            CustomView136(
                text83Text: text83Text,
                image105Path: image105Path)
                .frame(width: 100, height: 16)
            Image(image106Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21.999, height: 20.99, alignment: .topLeading)
        }
        .frame(width: 365, height: 20.99, alignment: .topLeading)
    }
}

struct CustomView135_Previews: PreviewProvider {
    static var previews: some View {
        CustomView135()
    }
}
