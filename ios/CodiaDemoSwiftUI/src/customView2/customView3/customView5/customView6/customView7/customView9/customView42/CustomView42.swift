//
//  CustomView42.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView42: View {
    @State public var image25Path: String = "image25_I426841961"
    @State public var text19Text: String = "5"
    @State public var text20Text: String = "Lucy Liu"
    @State public var text21Text: String = "Morgan Stanley"
    @State public var text22Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView43(
                image25Path: image25Path,
                text19Text: text19Text,
                text20Text: text20Text,
                text21Text: text21Text,
                text22Text: text22Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 311, height: 392, alignment: .topLeading)
    }
}

struct CustomView42_Previews: PreviewProvider {
    static var previews: some View {
        CustomView42()
    }
}
