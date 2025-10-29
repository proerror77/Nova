//
//  CustomView284.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView284: View {
    @State public var image204Path: String = "image204_4957"
    @State public var text158Text: String = "Liam"
    @State public var text159Text: String = "Hello, how are you bro~"
    @State public var text160Text: String = "09:41 PM"
    @State public var image205Path: String = "image205_4966"
    @State public var text161Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(image204Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView285(
                text158Text: text158Text,
                text159Text: text159Text,
                text160Text: text160Text,
                image205Path: image205Path,
                text161Text: text161Text)
                .frame(height: 72)
        }
        .frame(width: 356, height: 72, alignment: .topLeading)
    }
}

struct CustomView284_Previews: PreviewProvider {
    static var previews: some View {
        CustomView284()
    }
}
