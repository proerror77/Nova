//
//  CustomView186.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView186: View {
    @State public var image132Path: String = "image132_4706"
    @State public var image133Path: String = "image133_4708"
    @State public var text98Text: String = "Account_two"
    @State public var text99Text: String = "Icered"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image132Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 21, alignment: .topLeading)
                .offset(x: 315, y: 32)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.68, green: 0.68, blue: 0.68, opacity: 1.00), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 349, height: 86)
            Image(image133Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 54, height: 54, alignment: .top)
                .offset(x: 17, y: 16)
            CustomView188(
                text98Text: text98Text,
                text99Text: text99Text)
                .frame(width: 161, height: 46)
                .offset(x: 88, y: 21)
        }
        .frame(width: 349, height: 86, alignment: .topLeading)
    }
}

struct CustomView186_Previews: PreviewProvider {
    static var previews: some View {
        CustomView186()
    }
}
