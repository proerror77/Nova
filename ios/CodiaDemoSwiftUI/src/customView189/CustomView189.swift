//
//  CustomView189.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView189: View {
    @State public var text100Text: String = "Bruce Li"
    @State public var image134Path: String = "image134_I471441875"
    @State public var image135Path: String = "image135_4715"
    @State public var image136Path: String = "image136_4717"
    @State public var image137Path: String = "image137_4719"
    @State public var text101Text: String = "Select the account you wish to add"
    @State public var image138Path: String = "image138_4721"
    @State public var image139Path: String = "image139_4724"
    @State public var text102Text: String = "Add an Icered account"
    @State public var image140Path: String = "image140_4734"
    @State public var image141Path: String = "image141_4736"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView190(
                text100Text: text100Text,
                image134Path: image134Path,
                image135Path: image135Path)
                .frame(width: 365, height: 20.99)
                .offset(x: 14, y: 67)
            Rectangle()
                .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .frame(width: 393, height: 113)
            Image(image136Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            Image(image137Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
                HStack {
                    Spacer()
                        Text(text101Text)
                            .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 18))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 107)
            Image(image138Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20, alignment: .topLeading)
                .offset(x: 22, y: 66)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.68, green: 0.68, blue: 0.68, opacity: 1.00), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 351, height: 56)
                .offset(x: 22, y: 147)
            CustomView194(
                image139Path: image139Path,
                text102Text: text102Text,
                image140Path: image140Path,
                image141Path: image141Path)
                .frame(width: 340.891, height: 60)
                .offset(x: 38, y: 145)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView189_Previews: PreviewProvider {
    static var previews: some View {
        CustomView189()
    }
}
