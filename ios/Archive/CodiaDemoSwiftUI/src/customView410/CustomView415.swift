//
//  CustomView415.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView415: View {
    @State public var image265Path: String = "image265_41346"
    @State public var text219Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 230) {
            CustomView416(
                image265Path: image265Path,
                text219Text: text219Text)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView415_Previews: PreviewProvider {
    static var previews: some View {
        CustomView415()
    }
}
