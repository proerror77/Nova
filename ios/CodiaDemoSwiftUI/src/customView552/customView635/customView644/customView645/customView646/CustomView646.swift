//
//  CustomView646.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView646: View {
    @State public var image448Path: String = "image448_42103"
    @State public var text306Text: String = "2"
    @State public var text307Text: String = "Lucy Liu"
    @State public var text308Text: String = "Morgan Stanley"
    @State public var text309Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image448Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView647(text306Text: text306Text)
                .frame(width: 35, height: 35)
            CustomView649(
                text307Text: text307Text,
                text308Text: text308Text)
                .frame(width: 99, height: 38)
            CustomView650(text309Text: text309Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView646_Previews: PreviewProvider {
    static var previews: some View {
        CustomView646()
    }
}
