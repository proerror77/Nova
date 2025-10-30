//
//  CustomView195.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView195: View {
    @State public var text102Text: String = "Add an Icered account"
    @State public var image140Path: String = "image140_4734"
    @State public var image141Path: String = "image141_4736"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView196(
                text102Text: text102Text,
                image140Path: image140Path,
                image141Path: image141Path)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 319, alignment: .leading)
    }
}

struct CustomView195_Previews: PreviewProvider {
    static var previews: some View {
        CustomView195()
    }
}
