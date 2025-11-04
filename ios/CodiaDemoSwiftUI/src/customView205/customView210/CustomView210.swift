//
//  CustomView210.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView210: View {
    @State public var image150Path: String = "image150_4766"
    @State public var text111Text: String = "Apple iPhone17"
    @State public var text112Text: String = "Last active: Invalid Date"
    @State public var image151Path: String = "image151_4771"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image150Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 21, alignment: .topLeading)
                .offset(x: 315, y: 32)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.68, green: 0.68, blue: 0.68, opacity: 1.00), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 349, height: 86)
            CustomView212(
                text111Text: text111Text,
                text112Text: text112Text)
                .frame(width: 161, height: 46)
                .offset(x: 88, y: 21)
            Image(image151Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 31.212, height: 45.999, alignment: .topLeading)
                .offset(x: 28.393, y: 21)
        }
        .frame(width: 349, height: 86, alignment: .topLeading)
    }
}

struct CustomView210_Previews: PreviewProvider {
    static var previews: some View {
        CustomView210()
    }
}
