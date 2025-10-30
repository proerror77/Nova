//
//  CustomView720.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView720: View {
    @State public var image502Path: String = "image502_42285"
    @State public var text342Text: String = "1"
    @State public var text343Text: String = "Lucy Liu"
    @State public var text344Text: String = "Morgan Stanley"
    @State public var text345Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image502Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView721(text342Text: text342Text)
                .frame(width: 35, height: 35)
            CustomView723(
                text343Text: text343Text,
                text344Text: text344Text)
                .frame(width: 99, height: 38)
            CustomView724(text345Text: text345Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView720_Previews: PreviewProvider {
    static var previews: some View {
        CustomView720()
    }
}
