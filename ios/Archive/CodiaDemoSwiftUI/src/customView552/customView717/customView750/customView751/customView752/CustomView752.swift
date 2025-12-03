//
//  CustomView752.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView752: View {
    @State public var image526Path: String = "image526_42365"
    @State public var text358Text: String = "5"
    @State public var text359Text: String = "Lucy Liu"
    @State public var text360Text: String = "Morgan Stanley"
    @State public var text361Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image526Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView753(text358Text: text358Text)
                .frame(width: 35, height: 35)
            CustomView755(
                text359Text: text359Text,
                text360Text: text360Text)
                .frame(width: 99, height: 38)
            CustomView756(text361Text: text361Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView752_Previews: PreviewProvider {
    static var previews: some View {
        CustomView752()
    }
}
