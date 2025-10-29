//
//  CustomView492.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView492: View {
    @State public var image305Path: String = "image305_41560"
    @State public var image306Path: String = "image306_41561"
    @State public var image307Path: String = "image307_41563"
    @State public var image308Path: String = "image308_41570"
    @State public var text244Text: String = "Eli"
    @State public var image309Path: String = "image309_41572"
    @State public var image310Path: String = "image310_41589"
    @State public var text245Text: String = "Uh-huh..."
    @State public var image311Path: String = "image311_41601"
    @State public var text246Text: String = "miss you"
    @State public var image312Path: String = "image312_41606"
    @State public var text247Text: String = "Hello, how are you bro~"
    @State public var text248Text: String = "2025/10/22  12:00"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                Rectangle()
                    .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                    .frame(width: 393, height: 852)
                Rectangle()
                    .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                    .frame(width: 393, height: 76)
                    .offset(y: 776)
                Rectangle()
                    .fill(Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.74, green: 0.74, blue: 0.74, opacity: 1.00), lineWidth: 1))
                    .frame(width: 393, height: 1)
                    .offset(y: 776)
                Rectangle()
                    .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                    .frame(width: 393, height: 113)
                Rectangle()
                    .fill(Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.74, green: 0.74, blue: 0.74, opacity: 1.00), lineWidth: 1))
                    .frame(width: 393, height: 1)
                    .offset(y: 114)
                Image(image305Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 393, height: 47, alignment: .topLeading)
                Image(image306Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 141, height: 5, alignment: .top)
                    .offset(x: 126, y: 836)
                Image(image307Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 350, height: 23, alignment: .topLeading)
                    .offset(x: 22, y: 68)
                CustomView498(
                    image308Path: image308Path,
                    text244Text: text244Text)
                    .frame(width: 86, height: 50)
                    .offset(x: 62, y: 54)
                Image(image309Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 375, height: 33, alignment: .topLeading)
                    .offset(x: 9, y: 783)
            }
            Group {
                CustomView499(
                    image310Path: image310Path,
                    text245Text: text245Text,
                    image311Path: image311Path,
                    text246Text: text246Text,
                    image312Path: image312Path,
                    text247Text: text247Text)
                    .frame(width: 369, height: 224)
                    .offset(x: 12, y: 152)
                    HStack {
                        Spacer()
                            Text(text248Text)
                                .foregroundColor(Color(red: 0.59, green: 0.59, blue: 0.59, opacity: 1.00))
                                .font(.custom("HelveticaNeue", size: 12))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 122)
            }
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView492_Previews: PreviewProvider {
    static var previews: some View {
        CustomView492()
    }
}
