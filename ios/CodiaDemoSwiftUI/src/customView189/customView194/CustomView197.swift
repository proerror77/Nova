//
//  CustomView197.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView197: View {
    @State public var text102Text: String = "Add an Icered account"
    @State public var image140Path: String = "image140_4734"
    @State public var image141Path: String = "image141_4736"
    var body: some View {
        HStack(alignment: .center, spacing: 173) {
            CustomView198(text102Text: text102Text)
            Image(image140Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 6, alignment: .leading)
            Image(image141Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 6, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView197_Previews: PreviewProvider {
    static var previews: some View {
        CustomView197()
    }
}
