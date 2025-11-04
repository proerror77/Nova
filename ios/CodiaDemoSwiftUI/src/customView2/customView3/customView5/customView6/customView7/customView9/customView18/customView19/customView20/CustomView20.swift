//
//  CustomView20.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView20: View {
    @State public var image7Path: String = "image7_I426841901"
    @State public var text7Text: String = "2"
    @State public var text8Text: String = "Lucy Liu"
    @State public var text9Text: String = "Morgan Stanley"
    @State public var text10Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image7Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView21(text7Text: text7Text)
                .frame(width: 35, height: 35)
            CustomView23(
                text8Text: text8Text,
                text9Text: text9Text)
                .frame(width: 99, height: 38)
            CustomView24(text10Text: text10Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView20_Previews: PreviewProvider {
    static var previews: some View {
        CustomView20()
    }
}
