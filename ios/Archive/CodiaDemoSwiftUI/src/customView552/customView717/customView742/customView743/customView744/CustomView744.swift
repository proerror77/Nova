//
//  CustomView744.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView744: View {
    @State public var image520Path: String = "image520_42345"
    @State public var text354Text: String = "4"
    @State public var text355Text: String = "Lucy Liu"
    @State public var text356Text: String = "Morgan Stanley"
    @State public var text357Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image520Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView745(text354Text: text354Text)
                .frame(width: 35, height: 35)
            CustomView747(
                text355Text: text355Text,
                text356Text: text356Text)
                .frame(width: 99, height: 38)
            CustomView748(text357Text: text357Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView744_Previews: PreviewProvider {
    static var previews: some View {
        CustomView744()
    }
}
