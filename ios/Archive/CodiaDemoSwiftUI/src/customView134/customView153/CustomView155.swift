//
//  CustomView155.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView155: View {
    @State public var text87Text: String = "Devices"
    @State public var image115Path: String = "image115_4627"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView156(
                text87Text: text87Text,
                image115Path: image115Path)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView155_Previews: PreviewProvider {
    static var previews: some View {
        CustomView155()
    }
}
