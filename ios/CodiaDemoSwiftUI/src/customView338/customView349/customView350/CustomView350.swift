//
//  CustomView350.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView350: View {
    @State public var text194Text: String = "Icered contacts above"
    @State public var image230Path: String = "image230_41106"
    @State public var text195Text: String = "Bruce Li (you)"
    @State public var text196Text: String = "+86 199xxxx6164"
    @State public var image231Path: String = "image231_41110"
    var body: some View {
        VStack(alignment: .center, spacing: -114) {
            CustomView351(
                text194Text: text194Text,
                image230Path: image230Path,
                text195Text: text195Text,
                text196Text: text196Text,
                image231Path: image231Path)
                .frame(width: 319, height: 97)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView350_Previews: PreviewProvider {
    static var previews: some View {
        CustomView350()
    }
}
