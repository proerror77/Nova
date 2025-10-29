//
//  CustomView564.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView564: View {
    @State public var image388Path: String = "image388_41901"
    @State public var text266Text: String = "2"
    @State public var text267Text: String = "Lucy Liu"
    @State public var text268Text: String = "Morgan Stanley"
    @State public var text269Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image388Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView565(text266Text: text266Text)
                .frame(width: 35, height: 35)
            CustomView567(
                text267Text: text267Text,
                text268Text: text268Text)
                .frame(width: 99, height: 38)
            CustomView568(text269Text: text269Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView564_Previews: PreviewProvider {
    static var previews: some View {
        CustomView564()
    }
}
