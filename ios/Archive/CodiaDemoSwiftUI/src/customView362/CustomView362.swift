//
//  CustomView362.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView362: View {
    @State public var image237Path: String = "image237_41229"
    @State public var image238Path: String = "image238_41234"
    @State public var text200Text: String = "Search"
    @State public var image239Path: String = "image239_41236"
    @State public var text201Text: String = "Add members"
    @State public var text202Text: String = "0/256"
    @State public var image240Path: String = "image240_41240"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                .frame(width: 393, height: 852)
            Rectangle()
                .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .frame(width: 393, height: 113)
            Image(image237Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.74, green: 0.74, blue: 0.74, opacity: 1.00), lineWidth: 1))
                .frame(width: 393, height: 1)
                .offset(y: 114)
            CustomView366(
                image238Path: image238Path,
                text200Text: text200Text)
                .frame(width: 349, height: 32)
                .offset(x: 22, y: 130)
            Image(image239Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 350, height: 23, alignment: .topLeading)
                .offset(x: 22, y: 66)
                HStack {
                    Spacer()
                        Text(text201Text)
                            .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 24))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 68)
                HStack {
                    Spacer()
                        Text(text202Text)
                            .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25, opacity: 1.00))
                            .font(.custom("HelveticaNeue", size: 12))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 91)
            Image(image240Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView362_Previews: PreviewProvider {
    static var previews: some View {
        CustomView362()
    }
}
