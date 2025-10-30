//
//  CustomView471.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView471: View {
    @State public var image294Path: String = "image294_41490"
    @State public var image295Path: String = "image295_41492"
    @State public var image296Path: String = "image296_41494"
    @State public var text238Text: String = "Drafts"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                .frame(width: 393, height: 852)
            Rectangle()
                .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .frame(width: 393, height: 113)
            Image(image294Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            Image(image295Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 13, height: 23, alignment: .topLeading)
                .offset(x: 22, y: 66)
            Rectangle()
                .fill(Color.clear)
                .frame(width: 101, height: 20)
                .offset(x: 157, y: 168)
            Image(image296Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
                HStack {
                    Spacer()
                        Text(text238Text)
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
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.75, green: 0.75, blue: 0.75, opacity: 1.00), lineWidth: 1))
                .frame(width: 393, height: 1)
                .offset(y: 114)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView471_Previews: PreviewProvider {
    static var previews: some View {
        CustomView471()
    }
}
