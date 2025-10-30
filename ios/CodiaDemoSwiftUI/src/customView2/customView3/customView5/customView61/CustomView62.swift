//
//  CustomView62.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView62: View {
    @State public var image47Path: String = "image47_4351"
    @State public var text36Text: String = "93"
    @State public var text37Text: String = "kyleegigstead Cyborg dreams"
    @State public var text38Text: String = "kyleegigstead Cyborg dreams"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView63(
                image47Path: image47Path,
                text36Text: text36Text)
                .frame(width: 40.43, height: 18.654)
                .offset(x: 319.207, y: 3)
            Text(text37Text)
                .foregroundColor(Color(red: 0.14, green: 0.09, blue: 0.08, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 16))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
            Text(text38Text)
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

struct CustomView62_Previews: PreviewProvider {
    static var previews: some View {
        CustomView62()
    }
}
