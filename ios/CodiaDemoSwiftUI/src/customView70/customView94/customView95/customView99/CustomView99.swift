//
//  CustomView99.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView99: View {
    @State public var text64Text: String = "kyleegigstead Cyborg dreams"
    @State public var text65Text: String = "kyleegigstead Cyborg dreams"
    @State public var image83Path: String = "image83_4487"
    @State public var text66Text: String = "2293"
    var body: some View {
        HStack(alignment: .top, spacing: 36) {
            CustomView100(
                text64Text: text64Text,
                text65Text: text65Text)
                .frame(width: 111)
            CustomView101(
                image83Path: image83Path,
                text66Text: text66Text)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView99_Previews: PreviewProvider {
    static var previews: some View {
        CustomView99()
    }
}
