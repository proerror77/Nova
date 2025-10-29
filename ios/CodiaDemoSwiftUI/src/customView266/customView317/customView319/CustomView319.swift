//
//  CustomView319.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView319: View {
    @State public var image214Path: String = "image214_41001"
    @State public var text178Text: String = "Liam"
    @State public var text179Text: String = "Hello, how are you bro~"
    @State public var text180Text: String = "09:41 PM"
    @State public var image215Path: String = "image215_41010"
    @State public var text181Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(image214Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView320(
                text178Text: text178Text,
                text179Text: text179Text,
                text180Text: text180Text,
                image215Path: image215Path,
                text181Text: text181Text)
                .frame(height: 72)
        }
        .frame(width: 356, height: 72, alignment: .topLeading)
    }
}

struct CustomView319_Previews: PreviewProvider {
    static var previews: some View {
        CustomView319()
    }
}
