//
//  CustomView36.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView36: View {
    @State public var image19Path: String = "image19_I426841941"
    @State public var text15Text: String = "4"
    @State public var text16Text: String = "Lucy Liu"
    @State public var text17Text: String = "Morgan Stanley"
    @State public var text18Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image19Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView37(text15Text: text15Text)
                .frame(width: 35, height: 35)
            CustomView39(
                text16Text: text16Text,
                text17Text: text17Text)
                .frame(width: 99, height: 38)
            CustomView40(text18Text: text18Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView36_Previews: PreviewProvider {
    static var previews: some View {
        CustomView36()
    }
}
