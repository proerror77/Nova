//
//  CustomView353.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView353: View {
    @State public var image230Path: String = "image230_41106"
    @State public var text195Text: String = "Bruce Li (you)"
    @State public var text196Text: String = "+86 199xxxx6164"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView354(
                image230Path: image230Path,
                text195Text: text195Text,
                text196Text: text196Text)
                .frame(height: 47)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 188, alignment: .leading)
    }
}

struct CustomView353_Previews: PreviewProvider {
    static var previews: some View {
        CustomView353()
    }
}
