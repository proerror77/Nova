//
//  CustomView447.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView447: View {
    @State public var image277Path: String = "image277_41399"
    @State public var text227Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 230) {
            CustomView448(
                image277Path: image277Path,
                text227Text: text227Text)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView447_Previews: PreviewProvider {
    static var previews: some View {
        CustomView447()
    }
}
