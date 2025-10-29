//
//  CustomView629.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView629: View {
    @State public var image436Path: String = "image436_42062"
    @State public var text298Text: String = "5"
    @State public var text299Text: String = "Lucy Liu"
    @State public var text300Text: String = "Morgan Stanley"
    @State public var text301Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image436Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView630(text298Text: text298Text)
                .frame(width: 35, height: 35)
            CustomView632(
                text299Text: text299Text,
                text300Text: text300Text)
                .frame(width: 99, height: 38)
            CustomView633(text301Text: text301Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView629_Previews: PreviewProvider {
    static var previews: some View {
        CustomView629()
    }
}
