//
//  CustomView217.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView217: View {
    @State public var text115Text: String = "Bruce Li"
    @State public var image154Path: String = "image154_I478641875"
    @State public var image155Path: String = "image155_4787"
    var body: some View {
        HStack(alignment: .center, spacing: 243) {
            CustomView218(
                text115Text: text115Text,
                image154Path: image154Path)
                .frame(width: 100, height: 16)
            Image(image155Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21.999, height: 20.99, alignment: .topLeading)
        }
        .frame(width: 365, height: 20.99, alignment: .topLeading)
    }
}

struct CustomView217_Previews: PreviewProvider {
    static var previews: some View {
        CustomView217()
    }
}
