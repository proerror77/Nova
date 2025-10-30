//
//  CustomView110.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView110: View {
    @State public var text71Text: String = "Bruce Li"
    @State public var image90Path: String = "image90_I451641875"
    @State public var image91Path: String = "image91_4517"
    @State public var image92Path: String = "image92_4520"
    @State public var text72Text: String = "Favorite"
    @State public var image93Path: String = "image93_4523"
    @State public var image94Path: String = "image94_4525"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView111(
                text71Text: text71Text,
                image90Path: image90Path,
                image91Path: image91Path)
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
            Image(image92Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 350, height: 23, alignment: .topLeading)
                .offset(x: 22, y: 66)
                HStack {
                    Spacer()
                        Text(text72Text)
                            .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 24))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 68)
            Image(image93Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            Image(image94Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView110_Previews: PreviewProvider {
    static var previews: some View {
        CustomView110()
    }
}
