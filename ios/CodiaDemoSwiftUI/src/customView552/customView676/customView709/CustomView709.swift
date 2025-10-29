//
//  CustomView709.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView709: View {
    @State public var image496Path: String = "image496_42264"
    @State public var text338Text: String = "5"
    @State public var text339Text: String = "Lucy Liu"
    @State public var text340Text: String = "Morgan Stanley"
    @State public var text341Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView710(
                image496Path: image496Path,
                text338Text: text338Text,
                text339Text: text339Text,
                text340Text: text340Text,
                text341Text: text341Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 311, height: 392, alignment: .topLeading)
    }
}

struct CustomView709_Previews: PreviewProvider {
    static var previews: some View {
        CustomView709()
    }
}
