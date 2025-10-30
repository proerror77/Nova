//
//  CustomView509.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView509: View {
    @State public var image321Path: String = "image321_I4175653003"
    @State public var image322Path: String = "image322_I4175653008"
    @State public var text249Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image321Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 219, height: 30, alignment: .topLeading)
                .offset(x: 87, y: -2)
            Image(image322Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 66.661, height: 11.336, alignment: .topLeading)
                .offset(x: 311.667, y: 17.331)
            CustomView510(text249Text: text249Text)
                .frame(width: 54, height: 21)
                .offset(x: 24, y: 12)
        }
        .frame(width: 393, height: 46.167, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView509_Previews: PreviewProvider {
    static var previews: some View {
        CustomView509()
    }
}
