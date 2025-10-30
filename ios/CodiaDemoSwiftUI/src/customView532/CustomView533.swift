//
//  CustomView533.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView533: View {
    @State public var image365Path: String = "image365_I4183253003"
    @State public var image366Path: String = "image366_I4183253008"
    @State public var text255Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image365Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 219, height: 30, alignment: .topLeading)
                .offset(x: 87, y: -2)
            Image(image366Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 66.661, height: 11.336, alignment: .topLeading)
                .offset(x: 311.667, y: 17.331)
            CustomView534(text255Text: text255Text)
                .frame(width: 54, height: 21)
                .offset(x: 24, y: 12)
        }
        .frame(width: 393, height: 46.113, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView533_Previews: PreviewProvider {
    static var previews: some View {
        CustomView533()
    }
}
