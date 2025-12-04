//
//  CustomView516.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView516: View {
    @State public var image336Path: String = "image336_41783"
    @State public var image337Path: String = "image337_I4178453003"
    @State public var image338Path: String = "image338_I4178453008"
    @State public var text251Text: String = "9:41"
    @State public var image339Path: String = "image339_41786"
    @State public var image340Path: String = "image340_41787"
    @State public var image341Path: String = "image341_41788"
    @State public var image342Path: String = "image342_41789"
    @State public var image343Path: String = "image343_41794"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image336Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 578, height: 1266, alignment: .topLeading)
                .offset(x: -69, y: -247)
            CustomView517(
                image337Path: image337Path,
                image338Path: image338Path,
                text251Text: text251Text)
                .frame(width: 393, height: 46.167)
            Image(image339Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40, alignment: .topLeading)
                .offset(x: 244, y: 730)
            Image(image340Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 10, height: 10, alignment: .topLeading)
                .cornerRadius(5)
                .offset(x: 110, y: 8)
            Image(image341Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 6, height: 6, alignment: .topLeading)
                .cornerRadius(3)
                .offset(x: 271, y: 10)
            Image(image342Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64, alignment: .topLeading)
                .offset(x: 156, y: 717)
            Image(image343Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20, alignment: .topLeading)
                .offset(x: 22, y: 66)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView516_Previews: PreviewProvider {
    static var previews: some View {
        CustomView516()
    }
}
