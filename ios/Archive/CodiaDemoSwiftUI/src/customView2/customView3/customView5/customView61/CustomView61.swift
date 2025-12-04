//
//  CustomView61.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView61: View {
    @State public var image43Path: String = "image43_4334"
    @State public var image44Path: String = "image44_4335"
    @State public var text34Text: String = "Simone Carter"
    @State public var text35Text: String = "1d"
    @State public var image45Path: String = "image45_4342"
    @State public var image46Path: String = "image46_4343"
    @State public var image47Path: String = "image47_4351"
    @State public var text36Text: String = "93"
    @State public var text37Text: String = "kyleegigstead Cyborg dreams"
    @State public var text38Text: String = "kyleegigstead Cyborg dreams"
    @State public var image48Path: String = "image48_4358"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image43Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 378.039, height: 569.661, alignment: .top)
                .offset(y: 0.339)
            Image(image44Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 359.372, height: 458.257, alignment: .topLeading)
                .offset(x: 8, y: 49.765)
            Text(text34Text)
                .foregroundColor(Color(red: 0.02, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 12))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
                .offset(x: 44, y: 14)
            Text(text35Text)
                .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 8))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
                .offset(x: 44, y: 32)
            Image(image45Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 13.121, height: 15.655, alignment: .topLeading)
                .offset(x: 341.645, y: 20)
            Image(image46Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 29.042, height: 29.086, alignment: .topLeading)
                .offset(x: 8.114, y: 13.625)
            CustomView62(
                image47Path: image47Path,
                text36Text: text36Text,
                text37Text: text37Text,
                text38Text: text38Text)
                .frame(width: 359.637, height: 34)
                .offset(x: 8, y: 518)
            Image(image48Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 29.034, height: 29.111, alignment: .topLeading)
                .offset(x: 8, y: 13)
        }
        .frame(width: 378, height: 570, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView61_Previews: PreviewProvider {
    static var previews: some View {
        CustomView61()
    }
}
