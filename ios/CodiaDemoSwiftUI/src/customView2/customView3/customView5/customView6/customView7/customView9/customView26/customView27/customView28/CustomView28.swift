//
//  CustomView28.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView28: View {
    @State public var image13Path: String = "image13_I426841921"
    @State public var text11Text: String = "3"
    @State public var text12Text: String = "Lucy Liu"
    @State public var text13Text: String = "Morgan Stanley"
    @State public var text14Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image13Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView29(text11Text: text11Text)
                .frame(width: 35, height: 35)
            CustomView31(
                text12Text: text12Text,
                text13Text: text13Text)
                .frame(width: 99, height: 38)
            CustomView32(text14Text: text14Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView28_Previews: PreviewProvider {
    static var previews: some View {
        CustomView28()
    }
}
