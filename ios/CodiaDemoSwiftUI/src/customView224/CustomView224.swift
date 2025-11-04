//
//  CustomView224.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView224: View {
    @State public var text120Text: String = "Bruce Li"
    @State public var image161Path: String = "image161_I480141875"
    @State public var image162Path: String = "image162_4802"
    @State public var image163Path: String = "image163_4805"
    @State public var image164Path: String = "image164_4807"
    @State public var image165Path: String = "image165_4809"
    @State public var text121Text: String = "My Channels"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView225(
                text120Text: text120Text,
                image161Path: image161Path,
                image162Path: image162Path)
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
            Image(image163Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 350, height: 23, alignment: .topLeading)
                .offset(x: 22, y: 66)
            Image(image164Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            Image(image165Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
                HStack {
                    Spacer()
                        Text(text121Text)
                            .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 24))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 68)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView224_Previews: PreviewProvider {
    static var previews: some View {
        CustomView224()
    }
}
