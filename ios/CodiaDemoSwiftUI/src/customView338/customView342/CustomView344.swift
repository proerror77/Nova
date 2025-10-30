//
//  CustomView344.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView344: View {
    @State public var image224Path: String = "image224_41068"
    @State public var text191Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 230) {
            CustomView345(
                image224Path: image224Path,
                text191Text: text191Text)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView344_Previews: PreviewProvider {
    static var previews: some View {
        CustomView344()
    }
}
