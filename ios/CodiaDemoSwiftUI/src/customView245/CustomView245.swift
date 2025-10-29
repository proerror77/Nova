//
//  CustomView245.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView245: View {
    @State public var text139Text: String = "Bruce Li"
    @State public var image179Path: String = "image179_I487241875"
    @State public var image180Path: String = "image180_4873"
    @State public var image181Path: String = "image181_4876"
    @State public var image182Path: String = "image182_4878"
    @State public var image183Path: String = "image183_4880"
    @State public var text140Text: String = "News"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView246(
                text139Text: text139Text,
                image179Path: image179Path,
                image180Path: image180Path)
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
            Image(image181Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 350, height: 23, alignment: .topLeading)
                .offset(x: 22, y: 66)
            Image(image182Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            Image(image183Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
                HStack {
                    Spacer()
                        Text(text140Text)
                            .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 24))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 68)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView245_Previews: PreviewProvider {
    static var previews: some View {
        CustomView245()
    }
}
