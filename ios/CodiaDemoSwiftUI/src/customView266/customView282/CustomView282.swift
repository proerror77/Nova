//
//  CustomView282.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView282: View {
    @State public var image204Path: String = "image204_4957"
    @State public var text158Text: String = "Liam"
    @State public var text159Text: String = "Hello, how are you bro~"
    @State public var text160Text: String = "09:41 PM"
    @State public var image205Path: String = "image205_4966"
    @State public var text161Text: String = "1"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                .frame(width: 393, height: 80)
            CustomView284(
                image204Path: image204Path,
                text158Text: text158Text,
                text159Text: text159Text,
                text160Text: text160Text,
                image205Path: image205Path,
                text161Text: text161Text)
                .frame(width: 356, height: 72)
                .offset(x: 22, y: 4)
        }
        .frame(width: 393, height: 80, alignment: .topLeading)
    }
}

struct CustomView282_Previews: PreviewProvider {
    static var previews: some View {
        CustomView282()
    }
}
