//
//  CustomView77.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView77: View {
    @State public var text45Text: String = "Bruce Li"
    @State public var image70Path: String = "image70_I441241875"
    @State public var image71Path: String = "image71_4413"
    var body: some View {
        HStack(alignment: .center, spacing: 243) {
            CustomView78(
                text45Text: text45Text,
                image70Path: image70Path)
                .frame(width: 100, height: 16)
            Image(image71Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21.999, height: 20.99, alignment: .topLeading)
        }
        .frame(width: 365, height: 20.99, alignment: .topLeading)
    }
}

struct CustomView77_Previews: PreviewProvider {
    static var previews: some View {
        CustomView77()
    }
}
