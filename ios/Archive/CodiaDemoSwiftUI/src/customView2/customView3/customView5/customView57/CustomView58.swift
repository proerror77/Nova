//
//  CustomView58.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView58: View {
    @State public var image41Path: String = "image41_4321"
    @State public var text31Text: String = "93"
    @State public var text32Text: String = "kyleegigstead Cyborg dreams"
    @State public var text33Text: String = "kyleegigstead Cyborg dreams"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView59(
                image41Path: image41Path,
                text31Text: text31Text)
                .frame(width: 40.43, height: 18.654)
                .offset(x: 319.207, y: 3)
            Text(text32Text)
                .foregroundColor(Color(red: 0.14, green: 0.09, blue: 0.08, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 16))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
            Text(text33Text)
                .foregroundColor(Color(red: 0.45, green: 0.44, blue: 0.44, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 12))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
                .offset(y: 19)
        }
        .frame(width: 359.637, height: 34, alignment: .topLeading)
    }
}

struct CustomView58_Previews: PreviewProvider {
    static var previews: some View {
        CustomView58()
    }
}
