//
//  CustomView513.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView513: View {
    @State public var image329Path: String = "image329_I4177153003"
    @State public var image330Path: String = "image330_I4177153008"
    @State public var text250Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image329Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 219, height: 30, alignment: .topLeading)
                .offset(x: 87, y: -2)
            Image(image330Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 66.661, height: 11.336, alignment: .topLeading)
                .offset(x: 311.667, y: 17.331)
            CustomView514(text250Text: text250Text)
                .frame(width: 54, height: 21)
                .offset(x: 24, y: 12)
        }
        .frame(width: 393, height: 46.167, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView513_Previews: PreviewProvider {
    static var previews: some View {
        CustomView513()
    }
}
