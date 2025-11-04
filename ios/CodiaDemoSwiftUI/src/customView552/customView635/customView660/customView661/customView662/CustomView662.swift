//
//  CustomView662.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView662: View {
    @State public var image460Path: String = "image460_42143"
    @State public var text314Text: String = "4"
    @State public var text315Text: String = "Lucy Liu"
    @State public var text316Text: String = "Morgan Stanley"
    @State public var text317Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image460Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView663(text314Text: text314Text)
                .frame(width: 35, height: 35)
            CustomView665(
                text315Text: text315Text,
                text316Text: text316Text)
                .frame(width: 99, height: 38)
            CustomView666(text317Text: text317Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView662_Previews: PreviewProvider {
    static var previews: some View {
        CustomView662()
    }
}
