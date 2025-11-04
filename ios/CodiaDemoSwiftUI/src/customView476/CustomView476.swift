//
//  CustomView476.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView476: View {
    @State public var image297Path: String = "image297_41503"
    @State public var image298Path: String = "image298_41504"
    @State public var image299Path: String = "image299_41506"
    @State public var image300Path: String = "image300_41513"
    @State public var text239Text: String = "Eli"
    @State public var image301Path: String = "image301_41515"
    @State public var image302Path: String = "image302_41532"
    @State public var text240Text: String = "Uh-huh..."
    @State public var image303Path: String = "image303_41544"
    @State public var text241Text: String = "miss you"
    @State public var image304Path: String = "image304_41549"
    @State public var text242Text: String = "Hello, how are you bro~"
    @State public var text243Text: String = "2025/10/22  12:00"
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
                Image(image297Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 393, height: 47, alignment: .topLeading)
                Image(image298Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 141, height: 5, alignment: .top)
                    .offset(x: 126, y: 836)
                Image(image299Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 350, height: 23, alignment: .topLeading)
                    .offset(x: 22, y: 68)
                CustomView482(
                    image300Path: image300Path,
                    text239Text: text239Text)
                    .frame(width: 86, height: 50)
                    .offset(x: 62, y: 54)
                Image(image301Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 375, height: 33, alignment: .topLeading)
                    .offset(x: 9, y: 783)
            }
            Group {
                CustomView483(
                    image302Path: image302Path,
                    text240Text: text240Text,
                    image303Path: image303Path,
                    text241Text: text241Text,
                    image304Path: image304Path,
                    text242Text: text242Text)
                    .frame(width: 369, height: 224)
                    .offset(x: 12, y: 152)
                    HStack {
                        Spacer()
                            Text(text243Text)
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

struct CustomView476_Previews: PreviewProvider {
    static var previews: some View {
        CustomView476()
    }
}
