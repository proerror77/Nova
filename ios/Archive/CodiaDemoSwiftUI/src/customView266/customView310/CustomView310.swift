//
//  CustomView310.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView310: View {
    @State public var image212Path: String = "image212_4987"
    @State public var text174Text: String = "Liam"
    @State public var text175Text: String = "Hello, how are you bro~"
    @State public var text176Text: String = "09:41 PM"
    @State public var image213Path: String = "image213_4996"
    @State public var text177Text: String = "1"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                .frame(width: 393, height: 80)
            CustomView312(
                image212Path: image212Path,
                text174Text: text174Text,
                text175Text: text175Text,
                text176Text: text176Text,
                image213Path: image213Path,
                text177Text: text177Text)
                .frame(width: 356, height: 72)
                .offset(x: 22, y: 4)
        }
        .frame(width: 393, height: 80, alignment: .topLeading)
    }
}

struct CustomView310_Previews: PreviewProvider {
    static var previews: some View {
        CustomView310()
    }
}
