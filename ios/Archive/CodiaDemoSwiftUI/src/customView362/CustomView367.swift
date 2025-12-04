//
//  CustomView367.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView367: View {
    @State public var image238Path: String = "image238_41234"
    @State public var text200Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 230) {
            CustomView368(
                image238Path: image238Path,
                text200Text: text200Text)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView367_Previews: PreviewProvider {
    static var previews: some View {
        CustomView367()
    }
}
