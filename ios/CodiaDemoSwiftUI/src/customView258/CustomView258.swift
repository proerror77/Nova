//
//  CustomView258.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView258: View {
    @State public var text145Text: String = "Bruce Li"
    @State public var image189Path: String = "image189_I490141875"
    @State public var image190Path: String = "image190_4902"
    @State public var image191Path: String = "image191_4905"
    @State public var image192Path: String = "image192_4907"
    @State public var image193Path: String = "image193_4909"
    @State public var text146Text: String = "Bruce Li"
    @State public var text147Text: String = "Following"
    @State public var text148Text: String = "Followers"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView259(
                text145Text: text145Text,
                image189Path: image189Path,
                image190Path: image190Path)
                .frame(width: 365, height: 20.99)
                .offset(x: 14, y: 67)
            Rectangle()
                .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .frame(width: 393, height: 113)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.74, green: 0.74, blue: 0.74, opacity: 1.00), lineWidth: 1))
                .frame(width: 393, height: 1)
                .offset(y: 154)
            Image(image191Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 350, height: 23, alignment: .topLeading)
                .offset(x: 22, y: 66)
            Image(image192Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            Image(image193Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
                HStack {
                    Spacer()
                        Text(text146Text)
                            .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 24))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 68)
            CustomView263(
                text147Text: text147Text,
                text148Text: text148Text)
                .frame(width: 271, height: 20)
                .offset(x: 61, y: 121)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.81, green: 0.13, blue: 0.25, opacity: 1.00), lineWidth: 1))
                .frame(width: 196, height: 1)
                .offset(x: 197, y: 154)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView258_Previews: PreviewProvider {
    static var previews: some View {
        CustomView258()
    }
}
