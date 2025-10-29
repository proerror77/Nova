//
//  CustomView458.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView458: View {
    @State public var image282Path: String = "image282_41418"
    @State public var text231Text: String = "Align with the QR code for automatic recognition"
    @State public var image283Path: String = "image283_41420"
    @State public var image284Path: String = "image284_41423"
    @State public var image285Path: String = "image285_41424"
    @State public var image286Path: String = "image286_41426"
    @State public var text232Text: String = "Photos"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image282Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 805, alignment: .topLeading)
                .offset(y: 47)
                HStack {
                    Spacer()
                        Text(text231Text)
                            .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 14))
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 627)
            Image(image283Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20, alignment: .topLeading)
                .offset(x: 22, y: 66)
            Image(image284Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
            Image(image285Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            Image(image286Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 485, height: 214, alignment: .topLeading)
                .offset(x: -30, y: 243)
            Rectangle()
                .fill(Color.clear)
                .clipped()
                .frame(width: 47.84, height: 47.84)
                .offset(x: 140, y: 251)
            CustomView460(text232Text: text232Text)
                .frame(width: 60, height: 83)
                .offset(x: 166, y: 714)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView458_Previews: PreviewProvider {
    static var previews: some View {
        CustomView458()
    }
}
