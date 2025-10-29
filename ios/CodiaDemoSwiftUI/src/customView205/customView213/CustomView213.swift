//
//  CustomView213.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView213: View {
    @State public var image152Path: String = "image152_4775"
    @State public var text113Text: String = "Mac"
    @State public var text114Text: String = "Last active: Invalid Date"
    @State public var image153Path: String = "image153_4780"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image152Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 21, alignment: .topLeading)
                .offset(x: 315, y: 32)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.68, green: 0.68, blue: 0.68, opacity: 1.00), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 349, height: 86)
            CustomView215(
                text113Text: text113Text,
                text114Text: text114Text)
                .frame(width: 161, height: 46)
                .offset(x: 88, y: 21)
            Image(image153Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 29.002, alignment: .leading)
                .offset(x: 28, y: 28)
        }
        .frame(width: 349, height: 86, alignment: .topLeading)
    }
}

struct CustomView213_Previews: PreviewProvider {
    static var previews: some View {
        CustomView213()
    }
}
