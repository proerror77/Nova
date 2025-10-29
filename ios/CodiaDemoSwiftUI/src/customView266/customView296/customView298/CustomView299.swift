//
//  CustomView299.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView299: View {
    @State public var text166Text: String = "Liam"
    @State public var text167Text: String = "Hello, how are you bro~"
    @State public var text168Text: String = "09:41 PM"
    @State public var image209Path: String = "image209_I49694966"
    @State public var text169Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: -41) {
            CustomView300(
                text166Text: text166Text,
                text167Text: text167Text)
                .frame(width: 161, height: 46)
            CustomView301(
                text168Text: text168Text,
                image209Path: image209Path,
                text169Text: text169Text)
                .frame(width: 161)
        }
        .padding(EdgeInsets(top: 13, leading: 0, bottom: 10, trailing: 0))
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 72, alignment: .top)
    }
}

struct CustomView299_Previews: PreviewProvider {
    static var previews: some View {
        CustomView299()
    }
}
