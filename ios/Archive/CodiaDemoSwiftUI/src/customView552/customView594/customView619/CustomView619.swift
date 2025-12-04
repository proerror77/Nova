//
//  CustomView619.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView619: View {
    @State public var image430Path: String = "image430_42042"
    @State public var text294Text: String = "4"
    @State public var text295Text: String = "Lucy Liu"
    @State public var text296Text: String = "Morgan Stanley"
    @State public var text297Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView620(
                image430Path: image430Path,
                text294Text: text294Text,
                text295Text: text295Text,
                text296Text: text296Text,
                text297Text: text297Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 311, height: 392, alignment: .topLeading)
    }
}

struct CustomView619_Previews: PreviewProvider {
    static var previews: some View {
        CustomView619()
    }
}
