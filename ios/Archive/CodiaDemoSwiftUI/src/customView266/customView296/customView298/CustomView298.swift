//
//  CustomView298.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView298: View {
    @State public var image208Path: String = "image208_I49694957"
    @State public var text166Text: String = "Liam"
    @State public var text167Text: String = "Hello, how are you bro~"
    @State public var text168Text: String = "09:41 PM"
    @State public var image209Path: String = "image209_I49694966"
    @State public var text169Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(image208Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView299(
                text166Text: text166Text,
                text167Text: text167Text,
                text168Text: text168Text,
                image209Path: image209Path,
                text169Text: text169Text)
                .frame(height: 72)
        }
        .frame(width: 356, height: 72, alignment: .topLeading)
    }
}

struct CustomView298_Previews: PreviewProvider {
    static var previews: some View {
        CustomView298()
    }
}
