//
//  CustomView12.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView12: View {
    @State public var image1Path: String = "image1_I426841881"
    @State public var text3Text: String = "1"
    @State public var text4Text: String = "Lucy Liu"
    @State public var text5Text: String = "Morgan Stanley"
    @State public var text6Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image1Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView13(text3Text: text3Text)
                .frame(width: 35, height: 35)
            CustomView15(
                text4Text: text4Text,
                text5Text: text5Text)
                .frame(width: 99, height: 38)
            CustomView16(text6Text: text6Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView12_Previews: PreviewProvider {
    static var previews: some View {
        CustomView12()
    }
}
