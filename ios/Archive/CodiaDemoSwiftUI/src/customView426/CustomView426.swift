//
//  CustomView426.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView426: View {
    @State public var image270Path: String = "image270_41368"
    @State public var image271Path: String = "image271_41373"
    @State public var text223Text: String = "Search"
    @State public var image272Path: String = "image272_41375"
    @State public var text224Text: String = "Cancel"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                .frame(width: 393, height: 852)
            Rectangle()
                .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .frame(width: 393, height: 113)
            Image(image270Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.74, green: 0.74, blue: 0.74, opacity: 1.00), lineWidth: 1))
                .frame(width: 393, height: 1)
                .offset(y: 114)
            CustomView430(
                image271Path: image271Path,
                text223Text: text223Text)
                .frame(width: 310, height: 32)
                .offset(x: 22, y: 72)
            Image(image272Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            CustomView433(text224Text: text224Text)
                .frame(width: 44, height: 20)
                .offset(x: 340, y: 78)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView426_Previews: PreviewProvider {
    static var previews: some View {
        CustomView426()
    }
}
