//
//  CustomView183.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView183: View {
    @State public var image130Path: String = "image130_4699"
    @State public var image131Path: String = "image131_4701"
    @State public var text96Text: String = "Account_one"
    @State public var text97Text: String = "Icered"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image130Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 21, alignment: .topLeading)
                .offset(x: 315, y: 32)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.68, green: 0.68, blue: 0.68, opacity: 1.00), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 349, height: 86)
            Image(image131Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 54, height: 54, alignment: .top)
                .offset(x: 17, y: 16)
            CustomView185(
                text96Text: text96Text,
                text97Text: text97Text)
                .frame(width: 161, height: 46)
                .offset(x: 88, y: 21)
        }
        .frame(width: 349, height: 86, alignment: .topLeading)
    }
}

struct CustomView183_Previews: PreviewProvider {
    static var previews: some View {
        CustomView183()
    }
}
