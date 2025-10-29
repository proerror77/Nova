//
//  CustomView711.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView711: View {
    @State public var image496Path: String = "image496_42264"
    @State public var text338Text: String = "5"
    @State public var text339Text: String = "Lucy Liu"
    @State public var text340Text: String = "Morgan Stanley"
    @State public var text341Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image496Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView712(text338Text: text338Text)
                .frame(width: 35, height: 35)
            CustomView714(
                text339Text: text339Text,
                text340Text: text340Text)
                .frame(width: 99, height: 38)
            CustomView715(text341Text: text341Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView711_Previews: PreviewProvider {
    static var previews: some View {
        CustomView711()
    }
}
