//
//  CustomView431.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView431: View {
    @State public var image271Path: String = "image271_41373"
    @State public var text223Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 230) {
            CustomView432(
                image271Path: image271Path,
                text223Text: text223Text)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView431_Previews: PreviewProvider {
    static var previews: some View {
        CustomView431()
    }
}
