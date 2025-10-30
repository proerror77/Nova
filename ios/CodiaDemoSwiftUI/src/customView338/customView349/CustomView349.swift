//
//  CustomView349.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView349: View {
    @State public var text194Text: String = "Icered contacts above"
    @State public var image230Path: String = "image230_41106"
    @State public var text195Text: String = "Bruce Li (you)"
    @State public var text196Text: String = "+86 199xxxx6164"
    @State public var image231Path: String = "image231_41110"
    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            CustomView350(
                text194Text: text194Text,
                image230Path: image230Path,
                text195Text: text195Text,
                text196Text: text196Text,
                image231Path: image231Path)
        }
        .frame(width: 350, height: 97, alignment: .top)
    }
}

struct CustomView349_Previews: PreviewProvider {
    static var previews: some View {
        CustomView349()
    }
}
