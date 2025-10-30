//
//  CustomView338.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView338: View {
    @State public var image223Path: String = "image223_41061"
    @State public var text190Text: String = "Add as friends"
    @State public var image224Path: String = "image224_41068"
    @State public var text191Text: String = "Search"
    @State public var image225Path: String = "image225_41070"
    @State public var image226Path: String = "image226_41076"
    @State public var image227Path: String = "image227_41083"
    @State public var text192Text: String = "Bruce Li"
    @State public var image228Path: String = "image228_41093"
    @State public var text193Text: String = "Share invitation link "
    @State public var image229Path: String = "image229_41097"
    @State public var text194Text: String = "Icered contacts above"
    @State public var image230Path: String = "image230_41106"
    @State public var text195Text: String = "Bruce Li (you)"
    @State public var text196Text: String = "+86 199xxxx6164"
    @State public var image231Path: String = "image231_41110"
    @State public var image232Path: String = "image232_41114"
    @State public var text197Text: String = "Add a contact"
    @State public var image233Path: String = "image233_41121"
    @State public var text198Text: String = "Mobile phone contacts"
    @State public var image234Path: String = "image234_41125"
    @State public var text199Text: String = "Scan the code"
    @State public var image235Path: String = "image235_41132"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                Rectangle()
                    .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                    .frame(width: 393, height: 852)
                Rectangle()
                    .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                    .frame(width: 393, height: 113)
                Image(image223Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 393, height: 47, alignment: .topLeading)
                Rectangle()
                    .fill(Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.74, green: 0.74, blue: 0.74, opacity: 1.00), lineWidth: 1))
                    .frame(width: 393, height: 1)
                    .offset(y: 114)
                    HStack {
                        Spacer()
                            Text(text190Text)
                                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                                .font(.custom("HelveticaNeue-Medium", size: 24))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 68)
                CustomView342(
                    image224Path: image224Path,
                    text191Text: text191Text,
                    image225Path: image225Path)
                    .frame(width: 349, height: 32)
                    .offset(x: 22, y: 130)
                Image(image226Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 350, height: 23, alignment: .topLeading)
                    .offset(x: 22, y: 66)
                CustomView346(
                    image227Path: image227Path,
                    text192Text: text192Text)
                    .frame(width: 172, height: 205)
                    .offset(x: 110, y: 184)
                CustomView347(
                    image228Path: image228Path,
                    text193Text: text193Text)
                    .frame(width: 350, height: 35)
                    .offset(x: 21, y: 689)
                Image(image229Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 350, height: 67, alignment: .topLeading)
                    .offset(x: 21, y: 601)
            }
            Group {
                CustomView349(
                    text194Text: text194Text,
                    image230Path: image230Path,
                    text195Text: text195Text,
                    text196Text: text196Text,
                    image231Path: image231Path)
                    .frame(width: 350, height: 97)
                    .offset(x: 21, y: 571)
                CustomView356(
                    image232Path: image232Path,
                    text197Text: text197Text)
                    .frame(width: 350, height: 35)
                    .offset(x: 21, y: 521)
                CustomView358(
                    image233Path: image233Path,
                    text198Text: text198Text)
                    .frame(width: 350, height: 35)
                    .offset(x: 21, y: 466)
                CustomView360(
                    image234Path: image234Path,
                    text199Text: text199Text)
                    .frame(width: 350, height: 35)
                    .offset(x: 21, y: 411)
                Image(image235Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 141, height: 5, alignment: .top)
                    .offset(x: 126, y: 836)
            }
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView338_Previews: PreviewProvider {
    static var previews: some View {
        CustomView338()
    }
}
