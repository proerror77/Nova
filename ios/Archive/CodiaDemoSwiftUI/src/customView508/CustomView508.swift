//
//  CustomView508.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView508: View {
    @State public var image320Path: String = "image320_41755"
    @State public var image321Path: String = "image321_I4175653003"
    @State public var image322Path: String = "image322_I4175653008"
    @State public var text249Text: String = "9:41"
    @State public var image323Path: String = "image323_41758"
    @State public var image324Path: String = "image324_41761"
    @State public var image325Path: String = "image325_41762"
    @State public var image326Path: String = "image326_41763"
    @State public var image327Path: String = "image327_41768"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image320Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 578, height: 1266, alignment: .topLeading)
                .offset(x: -69, y: -247)
            CustomView509(
                image321Path: image321Path,
                image322Path: image322Path,
                text249Text: text249Text)
                .frame(width: 393, height: 46.167)
            Image(image323Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40, alignment: .topLeading)
                .offset(x: 244, y: 730)
            Image(image324Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 10, height: 10, alignment: .topLeading)
                .cornerRadius(5)
                .offset(x: 110, y: 8)
            Image(image325Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 6, height: 6, alignment: .topLeading)
                .cornerRadius(3)
                .offset(x: 271, y: 10)
            Image(image326Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64, alignment: .topLeading)
                .offset(x: 156, y: 717)
            Image(image327Path)
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

struct CustomView508_Previews: PreviewProvider {
    static var previews: some View {
        CustomView508()
    }
}
