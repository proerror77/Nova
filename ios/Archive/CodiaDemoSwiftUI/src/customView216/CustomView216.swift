//
//  CustomView216.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView216: View {
    @State public var text115Text: String = "Bruce Li"
    @State public var image154Path: String = "image154_I478641875"
    @State public var image155Path: String = "image155_4787"
    @State public var image156Path: String = "image156_4789"
    @State public var image157Path: String = "image157_4791"
    @State public var image158Path: String = "image158_4793"
    @State public var text116Text: String = "Invite Friends"
    @State public var image159Path: String = "image159_I47954952"
    @State public var text117Text: String = "Search"
    @State public var image160Path: String = "image160_I479741093"
    @State public var text118Text: String = "Share invitation link "
    @State public var text119Text: String = "You have 3 invitations left."
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView217(
                text115Text: text115Text,
                image154Path: image154Path,
                image155Path: image155Path)
                .frame(width: 365, height: 20.99)
                .offset(x: 14, y: 67)
            Rectangle()
                .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .frame(width: 393, height: 113)
            Image(image156Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 350, height: 23, alignment: .topLeading)
                .offset(x: 22, y: 67)
            Image(image157Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            Image(image158Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
                HStack {
                    Spacer()
                        Text(text116Text)
                            .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 24))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 68)
            CustomView220(
                image159Path: image159Path,
                text117Text: text117Text)
                .frame(width: 349, height: 32)
                .offset(x: 22, y: 130)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.74, green: 0.74, blue: 0.74, opacity: 1.00), lineWidth: 1))
                .frame(width: 393, height: 1)
                .offset(y: 114)
            CustomView222(
                image160Path: image160Path,
                text118Text: text118Text)
                .frame(width: 350, height: 35)
                .offset(x: 21, y: 178)
                HStack {
                    Spacer()
                        Text(text119Text)
                            .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                            .font(.custom("HelveticaNeue", size: 12))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 223)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView216_Previews: PreviewProvider {
    static var previews: some View {
        CustomView216()
    }
}
