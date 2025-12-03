//
//  CustomView710.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView710: View {
    @State public var image496Path: String = "image496_42264"
    @State public var text338Text: String = "5"
    @State public var text339Text: String = "Lucy Liu"
    @State public var text340Text: String = "Morgan Stanley"
    @State public var text341Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView711(
                image496Path: image496Path,
                text338Text: text338Text,
                text339Text: text339Text,
                text340Text: text340Text,
                text341Text: text341Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView710_Previews: PreviewProvider {
    static var previews: some View {
        CustomView710()
    }
}
