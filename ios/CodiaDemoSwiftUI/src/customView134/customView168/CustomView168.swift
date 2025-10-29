//
//  CustomView168.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView168: View {
    @State public var image120Path: String = "image120_4656"
    @State public var text90Text: String = "My Channels"
    @State public var image121Path: String = "image121_4666"
    var body: some View {
        HStack(alignment: .center) {
            Image(image120Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 21.891, alignment: .leading)
            CustomView169(
                text90Text: text90Text,
                image121Path: image121Path)
                .frame(width: 319)
        }
        .frame(width: 340.891, height: 60, alignment: .topLeading)
    }
}

struct CustomView168_Previews: PreviewProvider {
    static var previews: some View {
        CustomView168()
    }
}
