//
//  CustomView54.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView54: View {
    @State public var image35Path: String = "image35_4291"
    @State public var text26Text: String = "93"
    @State public var text27Text: String = "kyleegigstead Cyborg dreams"
    @State public var text28Text: String = "kyleegigstead Cyborg dreams"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView55(
                image35Path: image35Path,
                text26Text: text26Text)
                .frame(width: 40.43, height: 18.654)
                .offset(x: 319.207, y: 3)
            Text(text27Text)
                .foregroundColor(Color(red: 0.14, green: 0.09, blue: 0.08, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 16))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
            Text(text28Text)
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

struct CustomView54_Previews: PreviewProvider {
    static var previews: some View {
        CustomView54()
    }
}
