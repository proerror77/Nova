//
//  CustomView695.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView695: View {
    @State public var image484Path: String = "image484_42224"
    @State public var text330Text: String = "3"
    @State public var text331Text: String = "Lucy Liu"
    @State public var text332Text: String = "Morgan Stanley"
    @State public var text333Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image484Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView696(text330Text: text330Text)
                .frame(width: 35, height: 35)
            CustomView698(
                text331Text: text331Text,
                text332Text: text332Text)
                .frame(width: 99, height: 38)
            CustomView699(text333Text: text333Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView695_Previews: PreviewProvider {
    static var previews: some View {
        CustomView695()
    }
}
