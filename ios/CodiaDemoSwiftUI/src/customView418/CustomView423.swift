//
//  CustomView423.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView423: View {
    @State public var image268Path: String = "image268_41360"
    @State public var text221Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 230) {
            CustomView424(
                image268Path: image268Path,
                text221Text: text221Text)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView423_Previews: PreviewProvider {
    static var previews: some View {
        CustomView423()
    }
}
