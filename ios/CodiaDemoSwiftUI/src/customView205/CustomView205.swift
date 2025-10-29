//
//  CustomView205.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView205: View {
    @State public var text109Text: String = "Bruce Li"
    @State public var image145Path: String = "image145_I475541875"
    @State public var image146Path: String = "image146_4756"
    @State public var image147Path: String = "image147_4759"
    @State public var image148Path: String = "image148_4761"
    @State public var image149Path: String = "image149_4763"
    @State public var text110Text: String = "Devices"
    @State public var image150Path: String = "image150_4766"
    @State public var text111Text: String = "Apple iPhone17"
    @State public var text112Text: String = "Last active: Invalid Date"
    @State public var image151Path: String = "image151_4771"
    @State public var image152Path: String = "image152_4775"
    @State public var text113Text: String = "Mac"
    @State public var text114Text: String = "Last active: Invalid Date"
    @State public var image153Path: String = "image153_4780"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView206(
                text109Text: text109Text,
                image145Path: image145Path,
                image146Path: image146Path)
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
            Image(image147Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 350, height: 23, alignment: .topLeading)
                .offset(x: 22, y: 66)
            Image(image148Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            Image(image149Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
                HStack {
                    Spacer()
                        Text(text110Text)
                            .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 24))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 68)
            CustomView210(
                image150Path: image150Path,
                text111Text: text111Text,
                text112Text: text112Text,
                image151Path: image151Path)
                .frame(width: 349, height: 86)
                .offset(x: 22, y: 129)
            CustomView213(
                image152Path: image152Path,
                text113Text: text113Text,
                text114Text: text114Text,
                image153Path: image153Path)
                .frame(width: 349, height: 86)
                .offset(x: 22, y: 230)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView205_Previews: PreviewProvider {
    static var previews: some View {
        CustomView205()
    }
}
