//
//  CustomView743.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView743: View {
    @State public var image520Path: String = "image520_42345"
    @State public var text354Text: String = "4"
    @State public var text355Text: String = "Lucy Liu"
    @State public var text356Text: String = "Morgan Stanley"
    @State public var text357Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView744(
                image520Path: image520Path,
                text354Text: text354Text,
                text355Text: text355Text,
                text356Text: text356Text,
                text357Text: text357Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView743_Previews: PreviewProvider {
    static var previews: some View {
        CustomView743()
    }
}
