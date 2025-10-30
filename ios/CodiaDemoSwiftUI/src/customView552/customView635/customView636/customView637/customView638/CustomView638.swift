//
//  CustomView638.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView638: View {
    @State public var image442Path: String = "image442_42083"
    @State public var text302Text: String = "1"
    @State public var text303Text: String = "Lucy Liu"
    @State public var text304Text: String = "Morgan Stanley"
    @State public var text305Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image442Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView639(text302Text: text302Text)
                .frame(width: 35, height: 35)
            CustomView641(
                text303Text: text303Text,
                text304Text: text304Text)
                .frame(width: 99, height: 38)
            CustomView642(text305Text: text305Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView638_Previews: PreviewProvider {
    static var previews: some View {
        CustomView638()
    }
}
