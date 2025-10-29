//
//  CustomView134.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView134: View {
    @State public var text83Text: String = "Bruce Li"
    @State public var image105Path: String = "image105_I457541875"
    @State public var image106Path: String = "image106_4576"
    @State public var image107Path: String = "image107_4579"
    @State public var image108Path: String = "image108_4581"
    @State public var image109Path: String = "image109_4583"
    @State public var text84Text: String = "Settings"
    @State public var image110Path: String = "image110_4590"
    @State public var text85Text: String = "Profile Settings"
    @State public var image111Path: String = "image111_4600"
    @State public var image112Path: String = "image112_4604"
    @State public var text86Text: String = "Alias Accounts"
    @State public var image113Path: String = "image113_4614"
    @State public var image114Path: String = "image114_4617"
    @State public var text87Text: String = "Devices"
    @State public var image115Path: String = "image115_4627"
    @State public var image116Path: String = "image116_4630"
    @State public var text88Text: String = "Invite Friends"
    @State public var image117Path: String = "image117_4640"
    @State public var image118Path: String = "image118_4643"
    @State public var text89Text: String = "Sign Out"
    @State public var image119Path: String = "image119_4653"
    @State public var image120Path: String = "image120_4656"
    @State public var text90Text: String = "My Channels"
    @State public var image121Path: String = "image121_4666"
    @State public var image122Path: String = "image122_4669"
    @State public var text91Text: String = "Dark Mode"
    @State public var image123Path: String = "image123_4679"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                CustomView135(
                    text83Text: text83Text,
                    image105Path: image105Path,
                    image106Path: image106Path)
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
                Image(image107Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 350, height: 23, alignment: .topLeading)
                    .offset(x: 22, y: 66)
                Image(image108Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 141, height: 5, alignment: .top)
                    .offset(x: 126, y: 836)
                Image(image109Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 393, height: 47, alignment: .topLeading)
                    HStack {
                        Spacer()
                            Text(text84Text)
                                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                                .font(.custom("HelveticaNeue-Medium", size: 24))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 68)
                Rectangle()
                    .fill(Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.68, green: 0.68, blue: 0.68, opacity: 1.00), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 351, height: 253)
                    .offset(x: 21, y: 134)
                Rectangle()
                    .fill(Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.68, green: 0.68, blue: 0.68, opacity: 1.00), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 351, height: 54)
                    .offset(x: 21, y: 401)
                Rectangle()
                    .fill(Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.68, green: 0.68, blue: 0.68, opacity: 1.00), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 351, height: 54)
                    .offset(x: 21, y: 471)
            }
            Group {
                CustomView142(
                    image110Path: image110Path,
                    text85Text: text85Text,
                    image111Path: image111Path)
                    .frame(width: 356.891, height: 60)
                    .offset(x: 21, y: 127)
                CustomView148(
                    image112Path: image112Path,
                    text86Text: text86Text,
                    image113Path: image113Path)
                    .frame(width: 340.891, height: 60)
                    .offset(x: 37, y: 177)
                CustomView153(
                    image114Path: image114Path,
                    text87Text: text87Text,
                    image115Path: image115Path)
                    .frame(width: 340.891, height: 60)
                    .offset(x: 37, y: 227)
                CustomView158(
                    image116Path: image116Path,
                    text88Text: text88Text,
                    image117Path: image117Path)
                    .frame(width: 340.891, height: 60)
                    .offset(x: 37, y: 277)
                CustomView163(
                    image118Path: image118Path,
                    text89Text: text89Text,
                    image119Path: image119Path)
                    .frame(width: 340.891, height: 60)
                    .offset(x: 37, y: 467)
                CustomView168(
                    image120Path: image120Path,
                    text90Text: text90Text,
                    image121Path: image121Path)
                    .frame(width: 340.891, height: 60)
                    .offset(x: 37, y: 327)
                CustomView173(
                    image122Path: image122Path,
                    text91Text: text91Text,
                    image123Path: image123Path)
                    .frame(width: 340.891, height: 60)
                    .offset(x: 37, y: 397)
            }
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView134_Previews: PreviewProvider {
    static var previews: some View {
        CustomView134()
    }
}
