//
//  CustomView129.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView129: View {
    @State public var text81Text: String = "Bruce Li"
    @State public var image100Path: String = "image100_I456341875"
    @State public var image101Path: String = "image101_4564"
    @State public var image102Path: String = "image102_4567"
    @State public var text82Text: String = "Share profile"
    @State public var image103Path: String = "image103_4570"
    @State public var image104Path: String = "image104_4572"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView130(
                text81Text: text81Text,
                image100Path: image100Path,
                image101Path: image101Path)
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
            Image(image102Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 350, height: 23, alignment: .topLeading)
                .offset(x: 22, y: 66)
                HStack {
                    Spacer()
                        Text(text82Text)
                            .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 24))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 68)
            Image(image103Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            Image(image104Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView129_Previews: PreviewProvider {
    static var previews: some View {
        CustomView129()
    }
}
