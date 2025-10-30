//
//  CustomView26.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView26: View {
    @State public var image13Path: String = "image13_I426841921"
    @State public var text11Text: String = "3"
    @State public var text12Text: String = "Lucy Liu"
    @State public var text13Text: String = "Morgan Stanley"
    @State public var text14Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView27(
                image13Path: image13Path,
                text11Text: text11Text,
                text12Text: text12Text,
                text13Text: text13Text,
                text14Text: text14Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 312, height: 392, alignment: .topLeading)
    }
}

struct CustomView26_Previews: PreviewProvider {
    static var previews: some View {
        CustomView26()
    }
}
