//
//  CustomView149.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView149: View {
    @State public var text86Text: String = "Alias Accounts"
    @State public var image113Path: String = "image113_4614"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView150(
                text86Text: text86Text,
                image113Path: image113Path)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 319, alignment: .leading)
    }
}

struct CustomView149_Previews: PreviewProvider {
    static var previews: some View {
        CustomView149()
    }
}
