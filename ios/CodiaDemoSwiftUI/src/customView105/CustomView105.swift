//
//  CustomView105.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView105: View {
    @State public var text69Text: String = "Bruce Li"
    @State public var image85Path: String = "image85_I450441875"
    @State public var image86Path: String = "image86_4505"
    @State public var image87Path: String = "image87_4508"
    @State public var text70Text: String = "Edit profile"
    @State public var image88Path: String = "image88_4511"
    @State public var image89Path: String = "image89_4513"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView106(
                text69Text: text69Text,
                image85Path: image85Path,
                image86Path: image86Path)
                .frame(width: 365, height: 20.99)
                .offset(x: 14, y: 67)
            Rectangle()
                .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .frame(width: 393, height: 113)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.74, green: 0.74, blue: 0.74, opacity: 1.00), lineWidth: 1))
                .frame(width: 393, height: 1)
                .offset(y: 114)
            Image(image87Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 350, height: 23, alignment: .topLeading)
                .offset(x: 22, y: 66)
                HStack {
                    Spacer()
                        Text(text70Text)
                            .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 24))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 68)
            Image(image88Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            Image(image89Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView105_Previews: PreviewProvider {
    static var previews: some View {
        CustomView105()
    }
}
