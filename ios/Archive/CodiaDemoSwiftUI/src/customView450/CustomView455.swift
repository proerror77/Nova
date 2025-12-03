//
//  CustomView455.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView455: View {
    @State public var image280Path: String = "image280_41412"
    @State public var text229Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 230) {
            CustomView456(
                image280Path: image280Path,
                text229Text: text229Text)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView455_Previews: PreviewProvider {
    static var previews: some View {
        CustomView455()
    }
}
