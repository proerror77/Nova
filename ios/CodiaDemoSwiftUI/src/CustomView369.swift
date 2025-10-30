//
//  CustomView369.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView369: View {
    @State public var image241Path: String = "image241_41245"
    @State public var image242Path: String = "image242_41247"
    @State public var text203Text: String = "Chat message"
    @State public var image243Path: String = "image243_41250"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                .frame(width: 393, height: 852)
            Rectangle()
                .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .frame(width: 393, height: 113)
            Image(image241Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.74, green: 0.74, blue: 0.74, opacity: 1.00), lineWidth: 1))
                .frame(width: 393, height: 1)
                .offset(y: 114)
            Image(image242Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 350, height: 23, alignment: .topLeading)
                .offset(x: 22, y: 66)
                HStack {
                    Spacer()
                        Text(text203Text)
                            .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 24))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 68)
            Image(image243Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView369_Previews: PreviewProvider {
    static var previews: some View {
        CustomView369()
    }
}
