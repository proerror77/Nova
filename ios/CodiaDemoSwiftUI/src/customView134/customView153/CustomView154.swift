//
//  CustomView154.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView154: View {
    @State public var text87Text: String = "Devices"
    @State public var image115Path: String = "image115_4627"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView155(
                text87Text: text87Text,
                image115Path: image115Path)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 319, alignment: .leading)
    }
}

struct CustomView154_Previews: PreviewProvider {
    static var previews: some View {
        CustomView154()
    }
}
