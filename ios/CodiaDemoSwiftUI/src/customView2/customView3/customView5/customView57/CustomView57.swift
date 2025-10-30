//
//  CustomView57.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView57: View {
    @State public var image37Path: String = "image37_4304"
    @State public var image38Path: String = "image38_4305"
    @State public var text29Text: String = "Simone Carter"
    @State public var text30Text: String = "1d"
    @State public var image39Path: String = "image39_4312"
    @State public var image40Path: String = "image40_4313"
    @State public var image41Path: String = "image41_4321"
    @State public var text31Text: String = "93"
    @State public var text32Text: String = "kyleegigstead Cyborg dreams"
    @State public var text33Text: String = "kyleegigstead Cyborg dreams"
    @State public var image42Path: String = "image42_4328"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image37Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 378.039, height: 569.661, alignment: .top)
                .offset(y: 0.339)
            Image(image38Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 359.372, height: 458.257, alignment: .topLeading)
                .offset(x: 8, y: 49.765)
            Text(text29Text)
                .foregroundColor(Color(red: 0.02, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 12))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
                .offset(x: 44, y: 14)
            Text(text30Text)
                .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 8))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
                .offset(x: 44, y: 32)
            Image(image39Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 13.121, height: 15.655, alignment: .topLeading)
                .offset(x: 341.645, y: 20)
            Image(image40Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 29.042, height: 29.086, alignment: .topLeading)
                .offset(x: 8.114, y: 13.625)
            CustomView58(
                image41Path: image41Path,
                text31Text: text31Text,
                text32Text: text32Text,
                text33Text: text33Text)
                .frame(width: 359.637, height: 34)
                .offset(x: 8, y: 518)
            Image(image42Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 29.034, height: 29.111, alignment: .topLeading)
                .offset(x: 8, y: 13)
        }
        .frame(width: 378, height: 570, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView57_Previews: PreviewProvider {
    static var previews: some View {
        CustomView57()
    }
}
