//
//  CustomView225.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView225: View {
    @State public var text120Text: String = "Bruce Li"
    @State public var image161Path: String = "image161_I480141875"
    @State public var image162Path: String = "image162_4802"
    var body: some View {
        HStack(alignment: .center, spacing: 243) {
            CustomView226(
                text120Text: text120Text,
                image161Path: image161Path)
                .frame(width: 100, height: 16)
            Image(image162Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21.999, height: 20.99, alignment: .topLeading)
        }
        .frame(width: 365, height: 20.99, alignment: .topLeading)
    }
}

struct CustomView225_Previews: PreviewProvider {
    static var previews: some View {
        CustomView225()
    }
}
