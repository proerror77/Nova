//
//  CustomView178.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView178: View {
    @State public var text92Text: String = "Bruce Li"
    @State public var image124Path: String = "image124_I468441875"
    @State public var image125Path: String = "image125_4685"
    @State public var image126Path: String = "image126_4688"
    @State public var image127Path: String = "image127_4690"
    @State public var image128Path: String = "image128_4692"
    @State public var text93Text: String = "Accounts"
    @State public var image129Path: String = "image129_4694"
    @State public var text94Text: String = "You can add or remove accounts in the account center."
    @State public var text95Text: String = "Add an account"
    @State public var image130Path: String = "image130_4699"
    @State public var image131Path: String = "image131_4701"
    @State public var text96Text: String = "Account_one"
    @State public var text97Text: String = "Icered"
    @State public var image132Path: String = "image132_4706"
    @State public var image133Path: String = "image133_4708"
    @State public var text98Text: String = "Account_two"
    @State public var text99Text: String = "Icered"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                CustomView179(
                    text92Text: text92Text,
                    image124Path: image124Path,
                    image125Path: image125Path)
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
                Image(image126Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 350, height: 23, alignment: .topLeading)
                    .offset(x: 22, y: 66)
                Image(image127Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 141, height: 5, alignment: .top)
                    .offset(x: 126, y: 836)
                Image(image128Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 393, height: 47, alignment: .topLeading)
                    HStack {
                        Spacer()
                            Text(text93Text)
                                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                                .font(.custom("HelveticaNeue-Medium", size: 24))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 68)
                Image(image129Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 349, height: 54, alignment: .topLeading)
                    .offset(x: 22, y: 129)
                    HStack {
                        Spacer()
                            Text(text94Text)
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                                .font(.custom("HelveticaNeue", size: 12))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 395)
                    HStack {
                        Spacer()
                            Text(text95Text)
                                .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25, opacity: 1.00))
                                .font(.custom("HelveticaNeue-Medium", size: 18))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 145)
            }
            Group {
                CustomView183(
                    image130Path: image130Path,
                    image131Path: image131Path,
                    text96Text: text96Text,
                    text97Text: text97Text)
                    .frame(width: 349, height: 86)
                    .offset(x: 22, y: 198)
                CustomView186(
                    image132Path: image132Path,
                    image133Path: image133Path,
                    text98Text: text98Text,
                    text99Text: text99Text)
                    .frame(width: 349, height: 86)
                    .offset(x: 22, y: 299)
            }
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView178_Previews: PreviewProvider {
    static var previews: some View {
        CustomView178()
    }
}
