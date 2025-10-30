//
//  CustomView742.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView742: View {
    @State public var image520Path: String = "image520_42345"
    @State public var text354Text: String = "4"
    @State public var text355Text: String = "Lucy Liu"
    @State public var text356Text: String = "Morgan Stanley"
    @State public var text357Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView743(
                image520Path: image520Path,
                text354Text: text354Text,
                text355Text: text355Text,
                text356Text: text356Text,
                text357Text: text357Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 311, height: 392, alignment: .topLeading)
    }
}

struct CustomView742_Previews: PreviewProvider {
    static var previews: some View {
        CustomView742()
    }
}
