//
//  CustomView521.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView521: View {
    @State public var image345Path: String = "image345_I4179753003"
    @State public var image346Path: String = "image346_I4179753008"
    @State public var text252Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image345Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 219, height: 30, alignment: .topLeading)
                .offset(x: 87, y: -2)
            Image(image346Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 66.661, height: 11.336, alignment: .topLeading)
                .offset(x: 311.667, y: 17.331)
            CustomView522(text252Text: text252Text)
                .frame(width: 54, height: 21)
                .offset(x: 24, y: 12)
        }
        .frame(width: 393, height: 46.167, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView521_Previews: PreviewProvider {
    static var previews: some View {
        CustomView521()
    }
}
