//
//  CustomView91.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView91: View {
    @State public var text59Text: String = "kyleegigstead Cyborg dreams"
    @State public var text60Text: String = "kyleegigstead Cyborg dreams"
    @State public var image79Path: String = "image79_4464"
    @State public var text61Text: String = "2293"
    var body: some View {
        HStack(alignment: .top, spacing: 36) {
            CustomView92(
                text59Text: text59Text,
                text60Text: text60Text)
                .frame(width: 111)
            CustomView93(
                image79Path: image79Path,
                text61Text: text61Text)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView91_Previews: PreviewProvider {
    static var previews: some View {
        CustomView91()
    }
}
