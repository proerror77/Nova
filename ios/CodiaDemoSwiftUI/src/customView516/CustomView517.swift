//
//  CustomView517.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView517: View {
    @State public var image337Path: String = "image337_I4178453003"
    @State public var image338Path: String = "image338_I4178453008"
    @State public var text251Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image337Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 219, height: 30, alignment: .topLeading)
                .offset(x: 87, y: -2)
            Image(image338Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 66.661, height: 11.336, alignment: .topLeading)
                .offset(x: 311.667, y: 17.331)
            CustomView518(text251Text: text251Text)
                .frame(width: 54, height: 21)
                .offset(x: 24, y: 12)
        }
        .frame(width: 393, height: 46.167, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView517_Previews: PreviewProvider {
    static var previews: some View {
        CustomView517()
    }
}
