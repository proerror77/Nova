//
//  CustomView242.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView242: View {
    @State public var image175Path: String = "image175_4856"
    @State public var image176Path: String = "image176_4858"
    @State public var image177Path: String = "image177_4859"
    @State public var text137Text: String = "Upload a new avatar"
    @State public var text138Text: String = "Make an avatar with Alice"
    @State public var image178Path: String = "image178_4867"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image175Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            Image(image176Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
            Image(image177Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 268, height: 268, alignment: .top)
                .offset(x: 62, y: 139)
            Rectangle()
                .fill(Color(red: 0.85, green: 0.85, blue: 0.85, opacity: 1.00))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 351, height: 88)
                .offset(x: 21, y: 459)
            Text(text137Text)
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
                .offset(x: 32, y: 471)
            Text(text138Text)
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
                .offset(x: 32, y: 514)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.91, green: 0.91, blue: 0.91, opacity: 1.00), lineWidth: 1))
                .frame(width: 351, height: 1)
                .offset(x: 21, y: 503)
            Image(image178Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 23, height: 23, alignment: .topLeading)
                .offset(x: 22, y: 66)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView242_Previews: PreviewProvider {
    static var previews: some View {
        CustomView242()
    }
}
