//
//  CustomView537.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView537: View {
    @State public var image371Path: String = "image371_I4184153003"
    @State public var image372Path: String = "image372_I4184153008"
    @State public var text256Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image371Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 219, height: 30, alignment: .topLeading)
                .offset(x: 87, y: -2)
            Image(image372Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 66.661, height: 11.336, alignment: .topLeading)
                .offset(x: 311.667, y: 17.331)
            CustomView538(text256Text: text256Text)
                .frame(width: 54, height: 21)
                .offset(x: 24, y: 12)
        }
        .frame(width: 393, height: 46.113, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView537_Previews: PreviewProvider {
    static var previews: some View {
        CustomView537()
    }
}
