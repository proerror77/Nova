//
//  CustomView410.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView410: View {
    @State public var image264Path: String = "image264_41341"
    @State public var image265Path: String = "image265_41346"
    @State public var text219Text: String = "Search"
    @State public var image266Path: String = "image266_41348"
    @State public var text220Text: String = "Cancel"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                .frame(width: 393, height: 852)
            Rectangle()
                .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .frame(width: 393, height: 113)
            Image(image264Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.74, green: 0.74, blue: 0.74, opacity: 1.00), lineWidth: 1))
                .frame(width: 393, height: 1)
                .offset(y: 114)
            CustomView414(
                image265Path: image265Path,
                text219Text: text219Text)
                .frame(width: 310, height: 32)
                .offset(x: 22, y: 72)
            Image(image266Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            CustomView417(text220Text: text220Text)
                .frame(width: 44, height: 20)
                .offset(x: 340, y: 78)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView410_Previews: PreviewProvider {
    static var previews: some View {
        CustomView410()
    }
}
