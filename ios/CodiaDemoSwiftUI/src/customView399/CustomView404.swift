//
//  CustomView404.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView404: View {
    @State public var image258Path: String = "image258_41321"
    @State public var text216Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 230) {
            CustomView405(
                image258Path: image258Path,
                text216Text: text216Text)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView404_Previews: PreviewProvider {
    static var previews: some View {
        CustomView404()
    }
}
