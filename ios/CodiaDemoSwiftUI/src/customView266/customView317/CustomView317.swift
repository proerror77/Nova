//
//  CustomView317.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView317: View {
    @State public var image214Path: String = "image214_41001"
    @State public var text178Text: String = "Liam"
    @State public var text179Text: String = "Hello, how are you bro~"
    @State public var text180Text: String = "09:41 PM"
    @State public var image215Path: String = "image215_41010"
    @State public var text181Text: String = "1"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                .frame(width: 393, height: 80)
            CustomView319(
                image214Path: image214Path,
                text178Text: text178Text,
                text179Text: text179Text,
                text180Text: text180Text,
                image215Path: image215Path,
                text181Text: text181Text)
                .frame(width: 356, height: 72)
                .offset(x: 22, y: 4)
        }
        .frame(width: 393, height: 80, alignment: .topLeading)
    }
}

struct CustomView317_Previews: PreviewProvider {
    static var previews: some View {
        CustomView317()
    }
}
