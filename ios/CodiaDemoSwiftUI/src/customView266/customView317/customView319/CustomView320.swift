//
//  CustomView320.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView320: View {
    @State public var text178Text: String = "Liam"
    @State public var text179Text: String = "Hello, how are you bro~"
    @State public var text180Text: String = "09:41 PM"
    @State public var image215Path: String = "image215_41010"
    @State public var text181Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: -41) {
            CustomView321(
                text178Text: text178Text,
                text179Text: text179Text)
                .frame(width: 161, height: 46)
            CustomView322(
                text180Text: text180Text,
                image215Path: image215Path,
                text181Text: text181Text)
                .frame(width: 161)
        }
        .padding(EdgeInsets(top: 13, leading: 0, bottom: 10, trailing: 0))
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 72, alignment: .top)
    }
}

struct CustomView320_Previews: PreviewProvider {
    static var previews: some View {
        CustomView320()
    }
}
