//
//  CustomView450.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView450: View {
    @State public var image279Path: String = "image279_41407"
    @State public var image280Path: String = "image280_41412"
    @State public var text229Text: String = "Search"
    @State public var image281Path: String = "image281_41414"
    @State public var text230Text: String = "Cancel"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                .frame(width: 393, height: 852)
            Rectangle()
                .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .frame(width: 393, height: 113)
            Image(image279Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.74, green: 0.74, blue: 0.74, opacity: 1.00), lineWidth: 1))
                .frame(width: 393, height: 1)
                .offset(y: 114)
            CustomView454(
                image280Path: image280Path,
                text229Text: text229Text)
                .frame(width: 310, height: 32)
                .offset(x: 22, y: 72)
            Image(image281Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            CustomView457(text230Text: text230Text)
                .frame(width: 44, height: 20)
                .offset(x: 340, y: 78)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView450_Previews: PreviewProvider {
    static var previews: some View {
        CustomView450()
    }
}
