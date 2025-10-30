//
//  CustomView524.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView524: View {
    @State public var image352Path: String = "image352_41809"
    @State public var image353Path: String = "image353_I4181053003"
    @State public var image354Path: String = "image354_I4181053008"
    @State public var text253Text: String = "9:41"
    @State public var image355Path: String = "image355_41812"
    @State public var image356Path: String = "image356_41815"
    @State public var image357Path: String = "image357_41820"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image352Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 578, height: 1266, alignment: .topLeading)
                .offset(x: -69, y: -247)
            CustomView525(
                image353Path: image353Path,
                image354Path: image354Path,
                text253Text: text253Text)
                .frame(width: 393, height: 46.113)
            Image(image355Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64, alignment: .topLeading)
                .offset(x: 156, y: 717)
            Image(image356Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40, alignment: .topLeading)
                .offset(x: 92, y: 729)
            Image(image357Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20, alignment: .topLeading)
                .offset(x: 22, y: 66)
        }
        .frame(width: 393, height: 851, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView524_Previews: PreviewProvider {
    static var previews: some View {
        CustomView524()
    }
}
