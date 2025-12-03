//
//  CustomView175.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView175: View {
    @State public var text91Text: String = "Dark Mode"
    @State public var image123Path: String = "image123_4679"
    var body: some View {
        VStack(alignment: .leading, spacing: 71) {
            CustomView176(
                text91Text: text91Text,
                image123Path: image123Path)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView175_Previews: PreviewProvider {
    static var previews: some View {
        CustomView175()
    }
}
