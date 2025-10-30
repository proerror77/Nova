//
//  CustomView229.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView229: View {
    @State public var text122Text: String = "Bruce Li"
    @State public var image166Path: String = "image166_I481341875"
    @State public var image167Path: String = "image167_4814"
    @State public var image168Path: String = "image168_4817"
    @State public var image169Path: String = "image169_4819"
    @State public var image170Path: String = "image170_4821"
    @State public var text123Text: String = "Profile Setting"
    @State public var text124Text: String = "Save"
    @State public var image171Path: String = "image171_4825"
    @State public var image172Path: String = "image172_4829"
    @State public var text125Text: String = "First name"
    @State public var text126Text: String = "Username"
    @State public var text127Text: String = "Gender"
    @State public var text128Text: String = "Location"
    @State public var text129Text: String = "00/00/0000"
    @State public var text130Text: String = "Date of Birth"
    @State public var text131Text: String = "bruceli"
    @State public var text132Text: String = "Bruce"
    @State public var text133Text: String = "Li"
    @State public var text134Text: String = "Male"
    @State public var text135Text: String = "China"
    @State public var text136Text: String = "Last name"
    @State public var image173Path: String = "image173_4853"
    @State public var image174Path: String = "image174_4854"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                CustomView230(
                    text122Text: text122Text,
                    image166Path: image166Path,
                    image167Path: image167Path)
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
                Image(image168Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 350, height: 23, alignment: .topLeading)
                    .offset(x: 22, y: 66)
                Image(image169Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 141, height: 5, alignment: .top)
                    .offset(x: 126, y: 836)
                Image(image170Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 393, height: 47, alignment: .topLeading)
                    HStack {
                        Spacer()
                            Text(text123Text)
                                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                                .font(.custom("HelveticaNeue-Medium", size: 24))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 68)
                CustomView234(text124Text: text124Text)
                    .frame(width: 42, height: 20)
                    .offset(x: 338, y: 70)
                Image(image171Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120.117, height: 120.117, alignment: .top)
                    .offset(x: 136, y: 144)
                Image(image172Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 27, height: 27, alignment: .topLeading)
                    .offset(x: 334, y: 476)
            }
            Group {
                CustomView235(
                    text125Text: text125Text,
                    text126Text: text126Text,
                    text127Text: text127Text,
                    text128Text: text128Text,
                    text129Text: text129Text,
                    text130Text: text130Text,
                    text131Text: text131Text,
                    text132Text: text132Text,
                    text133Text: text133Text,
                    text134Text: text134Text,
                    text135Text: text135Text,
                    text136Text: text136Text)
                    .frame(width: 351, height: 344)
                    .offset(x: 21, y: 296)
                Image(image173Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 5, height: 10, alignment: .topLeading)
                    .offset(x: 356, y: 549)
                Image(image174Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 5, height: 10, alignment: .topLeading)
                    .offset(x: 356, y: 613)
            }
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView229_Previews: PreviewProvider {
    static var previews: some View {
        CustomView229()
    }
}
