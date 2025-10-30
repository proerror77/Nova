//
//  CustomView529.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView529: View {
    @State public var image359Path: String = "image359_I4182353003"
    @State public var image360Path: String = "image360_I4182353008"
    @State public var text254Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image359Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 219, height: 30, alignment: .topLeading)
                .offset(x: 87, y: -2)
            Image(image360Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 66.661, height: 11.336, alignment: .topLeading)
                .offset(x: 311.667, y: 17.331)
            CustomView530(text254Text: text254Text)
                .frame(width: 54, height: 21)
                .offset(x: 24, y: 12)
        }
        .frame(width: 393, height: 46.113, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView529_Previews: PreviewProvider {
    static var previews: some View {
        CustomView529()
    }
}
