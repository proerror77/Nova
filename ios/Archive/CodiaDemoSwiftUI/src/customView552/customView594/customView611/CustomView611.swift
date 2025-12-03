//
//  CustomView611.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView611: View {
    @State public var image424Path: String = "image424_42022"
    @State public var text290Text: String = "3"
    @State public var text291Text: String = "Lucy Liu"
    @State public var text292Text: String = "Morgan Stanley"
    @State public var text293Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView612(
                image424Path: image424Path,
                text290Text: text290Text,
                text291Text: text291Text,
                text292Text: text292Text,
                text293Text: text293Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 312, height: 392, alignment: .topLeading)
    }
}

struct CustomView611_Previews: PreviewProvider {
    static var previews: some View {
        CustomView611()
    }
}
