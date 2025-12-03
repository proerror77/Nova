//
//  CustomView578.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView578: View {
    @State public var image400Path: String = "image400_41941"
    @State public var text274Text: String = "4"
    @State public var text275Text: String = "Lucy Liu"
    @State public var text276Text: String = "Morgan Stanley"
    @State public var text277Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView579(
                image400Path: image400Path,
                text274Text: text274Text,
                text275Text: text275Text,
                text276Text: text276Text,
                text277Text: text277Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 311, height: 392, alignment: .topLeading)
    }
}

struct CustomView578_Previews: PreviewProvider {
    static var previews: some View {
        CustomView578()
    }
}
