//
//  CustomView250.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView250: View {
    @State public var text141Text: String = "Bruce Li"
    @State public var image184Path: String = "image184_I488441875"
    @State public var image185Path: String = "image185_4885"
    @State public var image186Path: String = "image186_4889"
    @State public var image187Path: String = "image187_4891"
    @State public var image188Path: String = "image188_4893"
    @State public var text142Text: String = "Bruce Li"
    @State public var text143Text: String = "Following"
    @State public var text144Text: String = "Followers"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView251(
                text141Text: text141Text,
                image184Path: image184Path,
                image185Path: image185Path)
                .frame(width: 365, height: 20.99)
                .offset(x: 14, y: 67)
            Rectangle()
                .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .frame(width: 393, height: 113)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.74, green: 0.74, blue: 0.74, opacity: 1.00), lineWidth: 1))
                .frame(width: 393, height: 1)
                .offset(y: 154)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.81, green: 0.13, blue: 0.25, opacity: 1.00), lineWidth: 1))
                .frame(width: 196, height: 1)
                .offset(y: 154)
            Image(image186Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 350, height: 23, alignment: .topLeading)
                .offset(x: 22, y: 66)
            Image(image187Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            Image(image188Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
                HStack {
                    Spacer()
                        Text(text142Text)
                            .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 24))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 68)
            CustomView256(
                text143Text: text143Text,
                text144Text: text144Text)
                .frame(width: 271, height: 20)
                .offset(x: 61, y: 121)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView250_Previews: PreviewProvider {
    static var previews: some View {
        CustomView250()
    }
}
