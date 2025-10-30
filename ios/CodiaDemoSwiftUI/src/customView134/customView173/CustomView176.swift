//
//  CustomView176.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView176: View {
    @State public var text91Text: String = "Dark Mode"
    @State public var image123Path: String = "image123_4679"
    var body: some View {
        HStack(alignment: .center, spacing: 173) {
            CustomView177(
                text91Text: text91Text,
                image123Path: image123Path)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView176_Previews: PreviewProvider {
    static var previews: some View {
        CustomView176()
    }
}
