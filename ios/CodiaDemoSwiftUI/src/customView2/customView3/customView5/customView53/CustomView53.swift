//
//  CustomView53.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView53: View {
    @State public var image31Path: String = "image31_4274"
    @State public var image32Path: String = "image32_4275"
    @State public var text24Text: String = "Simone Carter"
    @State public var text25Text: String = "1d"
    @State public var image33Path: String = "image33_4282"
    @State public var image34Path: String = "image34_4283"
    @State public var image35Path: String = "image35_4291"
    @State public var text26Text: String = "93"
    @State public var text27Text: String = "kyleegigstead Cyborg dreams"
    @State public var text28Text: String = "kyleegigstead Cyborg dreams"
    @State public var image36Path: String = "image36_4298"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image31Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 378.039, height: 569.661, alignment: .top)
                .offset(y: 0.339)
            Image(image32Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 359.372, height: 458.257, alignment: .topLeading)
                .offset(x: 8, y: 49.765)
            Text(text24Text)
                .foregroundColor(Color(red: 0.02, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 12))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
                .offset(x: 44, y: 14)
            Text(text25Text)
                .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 8))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
                .offset(x: 44, y: 32)
            Image(image33Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 13.121, height: 15.655, alignment: .topLeading)
                .offset(x: 341.645, y: 20)
            Image(image34Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 29.042, height: 29.086, alignment: .topLeading)
                .offset(x: 8.114, y: 13.625)
            CustomView54(
                image35Path: image35Path,
                text26Text: text26Text,
                text27Text: text27Text,
                text28Text: text28Text)
                .frame(width: 359.637, height: 34)
                .offset(x: 8, y: 518)
            Image(image36Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 29.034, height: 29.111, alignment: .topLeading)
                .offset(x: 8, y: 13)
        }
        .frame(width: 378, height: 570, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView53_Previews: PreviewProvider {
    static var previews: some View {
        CustomView53()
    }
}
