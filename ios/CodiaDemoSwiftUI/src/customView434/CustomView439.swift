//
//  CustomView439.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView439: View {
    @State public var image274Path: String = "image274_41386"
    @State public var text225Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 230) {
            CustomView440(
                image274Path: image274Path,
                text225Text: text225Text)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView439_Previews: PreviewProvider {
    static var previews: some View {
        CustomView439()
    }
}
