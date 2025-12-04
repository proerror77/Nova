//
//  CustomView352.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView352: View {
    @State public var image230Path: String = "image230_41106"
    @State public var text195Text: String = "Bruce Li (you)"
    @State public var text196Text: String = "+86 199xxxx6164"
    @State public var image231Path: String = "image231_41110"
    var body: some View {
        HStack(alignment: .bottom, spacing: 123) {
            CustomView353(
                image230Path: image230Path,
                text195Text: text195Text,
                text196Text: text196Text)
                .frame(width: 188)
            Image(image231Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26.08, height: 48.08, alignment: .topLeading)
        }
        .frame(width: 337.08, height: 67, alignment: .topLeading)
    }
}

struct CustomView352_Previews: PreviewProvider {
    static var previews: some View {
        CustomView352()
    }
}
