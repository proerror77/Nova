//
//  CustomView525.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView525: View {
    @State public var image353Path: String = "image353_I4181053003"
    @State public var image354Path: String = "image354_I4181053008"
    @State public var text253Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image353Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 219, height: 30, alignment: .topLeading)
                .offset(x: 87, y: -2)
            Image(image354Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 66.661, height: 11.336, alignment: .topLeading)
                .offset(x: 311.667, y: 17.331)
            CustomView526(text253Text: text253Text)
                .frame(width: 54, height: 21)
                .offset(x: 24, y: 12)
        }
        .frame(width: 393, height: 46.113, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView525_Previews: PreviewProvider {
    static var previews: some View {
        CustomView525()
    }
}
