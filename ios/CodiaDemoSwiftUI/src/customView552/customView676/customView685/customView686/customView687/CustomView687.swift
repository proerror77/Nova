//
//  CustomView687.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView687: View {
    @State public var image478Path: String = "image478_42204"
    @State public var text326Text: String = "2"
    @State public var text327Text: String = "Lucy Liu"
    @State public var text328Text: String = "Morgan Stanley"
    @State public var text329Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image478Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView688(text326Text: text326Text)
                .frame(width: 35, height: 35)
            CustomView690(
                text327Text: text327Text,
                text328Text: text328Text)
                .frame(width: 99, height: 38)
            CustomView691(text329Text: text329Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView687_Previews: PreviewProvider {
    static var previews: some View {
        CustomView687()
    }
}
