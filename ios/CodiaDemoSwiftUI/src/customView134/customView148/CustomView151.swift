//
//  CustomView151.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView151: View {
    @State public var text86Text: String = "Alias Accounts"
    @State public var image113Path: String = "image113_4614"
    var body: some View {
        HStack(alignment: .center, spacing: 173) {
            CustomView152(text86Text: text86Text)
            Image(image113Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 6, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView151_Previews: PreviewProvider {
    static var previews: some View {
        CustomView151()
    }
}
