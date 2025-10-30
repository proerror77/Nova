//
//  CustomView613.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView613: View {
    @State public var image424Path: String = "image424_42022"
    @State public var text290Text: String = "3"
    @State public var text291Text: String = "Lucy Liu"
    @State public var text292Text: String = "Morgan Stanley"
    @State public var text293Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image424Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView614(text290Text: text290Text)
                .frame(width: 35, height: 35)
            CustomView616(
                text291Text: text291Text,
                text292Text: text292Text)
                .frame(width: 99, height: 38)
            CustomView617(text293Text: text293Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView613_Previews: PreviewProvider {
    static var previews: some View {
        CustomView613()
    }
}
