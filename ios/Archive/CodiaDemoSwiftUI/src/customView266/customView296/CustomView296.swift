//
//  CustomView296.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView296: View {
    @State public var image208Path: String = "image208_I49694957"
    @State public var text166Text: String = "Liam"
    @State public var text167Text: String = "Hello, how are you bro~"
    @State public var text168Text: String = "09:41 PM"
    @State public var image209Path: String = "image209_I49694966"
    @State public var text169Text: String = "1"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                .frame(width: 393, height: 80)
            CustomView298(
                image208Path: image208Path,
                text166Text: text166Text,
                text167Text: text167Text,
                text168Text: text168Text,
                image209Path: image209Path,
                text169Text: text169Text)
                .frame(width: 356, height: 72)
                .offset(x: 22, y: 4)
        }
        .frame(width: 393, height: 80, alignment: .topLeading)
    }
}

struct CustomView296_Previews: PreviewProvider {
    static var previews: some View {
        CustomView296()
    }
}
