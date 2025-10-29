//
//  CustomView156.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView156: View {
    @State public var text87Text: String = "Devices"
    @State public var image115Path: String = "image115_4627"
    var body: some View {
        HStack(alignment: .center, spacing: 173) {
            CustomView157(text87Text: text87Text)
            Image(image115Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 6, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView156_Previews: PreviewProvider {
    static var previews: some View {
        CustomView156()
    }
}
